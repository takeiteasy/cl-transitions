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
             (invoke-callbacks (state-on-exit source-state) event-data))
           ;; 5. Cancel any existing timeout
           (cancel-timeout machine)
           ;; 6. State change
           (setf (machine-current-state machine) dest-name)
           ;; 7. On-enter callbacks for dest state (skip for reflexive)
           (when (and dest-state (not is-reflexive))
             (invoke-callbacks (state-on-enter dest-state) event-data))
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

(defun fire (machine trigger &rest args)
  "Fire a trigger on the machine.
Returns the new state on success.
If the trigger is invalid and IGNORE-INVALID-TRIGGERS is NIL, signals INVALID-TRIGGER-ERROR.
If IGNORE-INVALID-TRIGGERS is T, returns NIL for invalid triggers.
If conditions block the transition, returns NIL."
  (let ((transitions (find-transitions-for-trigger machine trigger)))
    (cond
      ;; No valid transitions found
      ((null transitions)
       (if (machine-ignore-invalid-triggers machine)
           nil
           (error 'invalid-trigger-error
                  :machine machine
                  :trigger trigger
                  :current-state (machine-current-state machine)
                  :message (format nil "No transition for trigger ~A from state ~A"
                                   trigger (machine-current-state machine)))))
      ;; Try each matching transition until one succeeds
      (t
       (dolist (trans transitions)
         (let ((result (apply #'execute-transition machine trans args)))
           (when result
             (return-from fire result))))
       ;; All transitions had failing conditions
       nil))))

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
