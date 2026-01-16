;;;; triggers.lisp - Trigger execution for cl-transitions

(in-package #:cl-transitions)

(defun execute-transition (machine transition &rest args)
  "Execute a transition with the full callback sequence:
prepare -> conditions -> before -> on-exit -> [STATE CHANGE] -> on-enter -> after
Returns the new state on success, or NIL if conditions fail."
  (let* ((source-name (machine-current-state machine))
         (dest-name (transition-dest transition))
         (source-state (get-state machine source-name))
         (dest-state (get-state machine dest-name))
         (event-data (make-event-data machine transition source-name dest-name args)))
    ;; 1. Prepare callbacks
    (invoke-callbacks (transition-prepare transition) event-data)
    ;; 2. Check conditions
    (unless (check-conditions (transition-conditions transition) event-data)
      (return-from execute-transition nil))
    ;; 3. Before callbacks
    (invoke-callbacks (transition-before transition) event-data)
    ;; 4. On-exit callbacks from source state
    (when source-state
      (invoke-callbacks (state-on-exit source-state) event-data))
    ;; 5. State change
    (setf (machine-current-state machine) dest-name)
    ;; 6. On-enter callbacks for dest state
    (when dest-state
      (invoke-callbacks (state-on-enter dest-state) event-data))
    ;; 7. After callbacks
    (invoke-callbacks (transition-after transition) event-data)
    ;; Return the new state
    dest-name))

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
              (let ((event-data (make-event-data machine trans
                                                  (machine-current-state machine)
                                                  (transition-dest trans)
                                                  nil)))
                (check-conditions (transition-conditions trans) event-data)))
            transitions))))
