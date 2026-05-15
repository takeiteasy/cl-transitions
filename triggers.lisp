;;;; triggers.lisp - Trigger execution for cl-transitions

(in-package #:cl-transitions)

(defun find-auto-transition (machine state-name)
  "Find an auto-transition that can fire from STATE-NAME.
Returns the first auto-transition whose source matches and conditions pass,
or NIL if none found."
  (dolist (trans (machine-transitions machine))
    (when (and (transition-auto-p trans)
               (transition-matches-source-p trans state-name))
      (let* ((dest (resolve-transition-dest trans state-name))
             (event-data (make-event-data machine trans state-name dest nil)))
        (when (check-conditions (transition-conditions trans) event-data)
          (return-from find-auto-transition trans)))))
  nil)

(defun check-and-fire-auto-transition (machine)
  "Check for and fire any auto-transition from the current state.
Tracks recursion depth to prevent infinite loops.
Returns the final state after auto-transition chain, or current state if none."
  (let ((current (machine-current-state machine))
        (auto-trans (find-auto-transition machine (machine-current-state machine))))
    (when auto-trans
      ;; Check for infinite loop
      (let ((depth (incf (machine-auto-transition-depth machine)))
            (max-depth (machine-max-auto-transitions machine)))
        (when (> depth max-depth)
          (decf (machine-auto-transition-depth machine))
          (error 'auto-transition-loop-error
                 :machine machine
                 :depth depth
                 :max-depth max-depth
                 :message (format nil "Auto-transition loop: depth ~A exceeds max ~A"
                                  depth max-depth)))
        (unwind-protect
             (execute-transition machine auto-trans)
          (decf (machine-auto-transition-depth machine)))))
    current))

(defun enter-submachine (state)
  "Enter the sub-machine of STATE (if any). Sets it to its initial state."
  (let ((sub (state-submachine state)))
    (when sub
      (setf (machine-current-state sub) (machine-initial-state sub))
      (setup-state-timeout sub (machine-current-state sub)))))

(defun exit-submachine (state)
  "Exit the sub-machine of STATE (if any). Cancels its timeout."
  (let ((sub (state-submachine state)))
    (when sub
      (cancel-timeout sub))))

(defun execute-transition (machine transition &rest args)
  "Execute a transition with the full callback sequence:
prepare -> conditions -> before -> on-exit -> [STATE CHANGE] -> on-enter -> after -> finalize
For reflexive transitions (dest is :=, :same, or :internal), on-exit and on-enter
callbacks are skipped.
Finalize callbacks always run, even if conditions fail or errors occur.
Returns the new state on success, or NIL if conditions fail."
  (let* ((source-name (machine-current-state machine))
         (dest-name (resolve-transition-dest transition source-name))
         (is-reflexive (reflexive-dest-p (transition-dest transition)))
         (source-state (get-state machine source-name))
         (dest-state (get-state machine dest-name))
         (event-data (make-event-data machine transition source-name dest-name args))
         (result nil))
    ;; Track whether transition succeeded for finalize callbacks
    (setf (event-transition-succeeded event-data) nil)
    (unwind-protect
         (progn
           ;; 1. Prepare callbacks
           (invoke-callbacks (transition-prepare transition) event-data)
           ;; 2. Check conditions
           (unless (check-conditions (transition-conditions transition) event-data)
             (return-from execute-transition nil))
           ;; 3. Before callbacks
           (invoke-callbacks (transition-before transition) event-data)
           ;; 4. On-exit callbacks from source state (skip for reflexive)
           (when (and source-state (not is-reflexive))
             (invoke-callbacks (state-on-exit source-state) event-data)
             ;; Exit submachine if present
             (exit-submachine source-state))
           ;; 5. Cancel any existing timeout
           (cancel-timeout machine)
           ;; 6. State change
           (setf (machine-current-state machine) dest-name)
           ;; 7. On-enter callbacks for dest state (skip for reflexive)
           (when (and dest-state (not is-reflexive))
             (invoke-callbacks (state-on-enter dest-state) event-data)
             ;; Enter submachine if present
             (enter-submachine dest-state))
           ;; 8. Set up timeout for new state (skip for reflexive)
           (unless is-reflexive
             (setup-state-timeout machine dest-name))
           ;; 7. After callbacks
           (invoke-callbacks (transition-after transition) event-data)
           ;; 8. Check for auto-transitions (skip for reflexive to avoid loops)
           (unless is-reflexive
             (check-and-fire-auto-transition machine))
           ;; Mark as succeeded
           (setf (event-transition-succeeded event-data) t)
           (setf result (machine-current-state machine)))
      ;; 8. Finalize callbacks (always run)
      (invoke-finalize-callbacks (transition-finalize transition) event-data))
    result))

(defun fire-direct (machine trigger args)
  "Fire a trigger without queue management. Used internally during queue drain.
Invalid triggers are silently ignored."
  (let ((transitions (find-transitions-for-trigger machine trigger)))
    (when transitions
      (dolist (trans transitions)
        (let ((result (apply #'execute-transition machine trans args)))
          (when result
            (return result)))))))

(defun drain-queued-triggers (machine)
  "Process all queued triggers in FIFO order.
New triggers queued during drain (e.g. from callbacks) are also processed.
Invalid triggers during drain are silently ignored."
  (loop while (machine-processing-queue machine)
        do (let* ((entry (pop (machine-processing-queue machine)))
                  (trigger (car entry))
                  (args (cdr entry)))
             (fire-direct machine trigger args))))
             
(defun fire (machine trigger &rest args)
  "Fire a trigger on the machine.
Returns the new state on success.
If the trigger is invalid and IGNORE-INVALID-TRIGGERS is NIL, signals INVALID-TRIGGER-ERROR.
If IGNORE-INVALID-TRIGGERS is T, returns NIL for invalid triggers.
If conditions block the transition, returns NIL.

When QUEUED mode is enabled (see make-machine :queued), triggers fired during
transition processing are queued and processed sequentially after the current
transition completes. This prevents re-entrant trigger execution from callbacks."
  ;; Queued mode: if already processing, queue the trigger and return
  (when (and (machine-queued-p machine)
             (machine-processing-p machine))
    (setf (machine-processing-queue machine)
          (nconc (machine-processing-queue machine)
                 (list (cons trigger args))))
    (return-from fire nil))

  ;; Track whether we're entering a new processing session
  (let ((was-processing (machine-processing-p machine))
        (result nil))
    (unless was-processing
      (setf (machine-processing-p machine) t))
    (unwind-protect
         (block fire-body
           (let ((transitions (find-transitions-for-trigger machine trigger)))
             (cond
               ((null transitions)
                (if (machine-ignore-invalid-triggers machine)
                    (setf result nil)
                    (error 'invalid-trigger-error
                           :machine machine
                           :trigger trigger
                           :current-state (machine-current-state machine)
                           :message (format nil "No transition for trigger ~A from state ~A"
                                            trigger (machine-current-state machine)))))
               (t
                (dolist (trans transitions)
                  (let ((r (apply #'execute-transition machine trans args)))
                    (when r
                      (setf result r)
                      (return-from fire-body))))
                (setf result nil)))))
      ;; Unwind: drain queue and clear processing flag
      (drain-queued-triggers machine)
      (unless was-processing
        (setf (machine-processing-p machine) nil)))
    result))

(defun may-fire-p (machine trigger)
  "Check if TRIGGER can be fired from the current state.
Returns T if there is at least one valid transition for the trigger,
and all its conditions pass (if any). Returns NIL otherwise."
  (let ((transitions (find-transitions-for-trigger machine trigger)))
    (when transitions
      ;; Check if any transition's conditions would pass
      (some (lambda (trans)
              (let* ((current (machine-current-state machine))
                     (dest (resolve-transition-dest trans current))
                     (event-data (make-event-data machine trans current dest nil)))
                (check-conditions (transition-conditions trans) event-data)))
            transitions))))

;;; ---------------------------------------------------------------------------
;;; Dynamic Trigger Methods
;;; ---------------------------------------------------------------------------

(defvar *model-machine-map* (make-hash-table :test 'eq)
  "Global mapping from model objects to their associated machines.")

(defun model-machine (model)
  "Get the machine associated with MODEL, or NIL if none."
  (gethash model *model-machine-map*))

(defun (setf model-machine) (machine model)
  "Set the machine associated with MODEL."
  (setf (gethash model *model-machine-map*) machine))

(defun remove-model-machine (model)
  "Remove MODEL from the machine mapping."
  (remhash model *model-machine-map*))

(defun collect-triggers (machine)
  "Collect all unique trigger symbols from the machine's transitions."
  (delete-duplicates
   (mapcar #'transition-trigger (machine-transitions machine))))

(defun add-dynamic-triggers (machine)
  "Define trigger functions for each trigger on MACHINE's model.
When a model is associated with the machine, this creates a function
named by each trigger symbol that takes the model as argument and
fires the corresponding trigger on the machine.

Example:
  (let ((model (make-instance 'some-class)))
    (make-machine :states '(:a :b)
                  :initial :a
                  :model model
                  :transitions '((:trigger :go :source :a :dest :b)))
    (:go model))  ; calls (fire machine :go)"
  (let ((model (machine-model machine)))
    (when model
      (setf (model-machine model) machine)
      (dolist (trigger (collect-triggers machine))
        (setf (symbol-function trigger)
              (let ((trig trigger))
                (lambda (mdl &rest args)
                  (let ((m (model-machine mdl)))
                    (if m
                        (apply #'fire m trig args)
                        (error 'invalid-trigger-error
                               :machine nil
                               :trigger trig
                               :current-state nil
                               :message (format nil "Model ~A is not registered with any machine"
                                                mdl)))))))))))
