;;;; timeouts.lisp - Timeout functionality for cl-transitions

(in-package #:cl-transitions)

(defun cancel-timeout (machine)
  "Cancel any pending timeout for MACHINE.
Thread-safe operation using the machine's timeout lock.
Returns T if a timeout was cancelled, NIL otherwise."
  (bt:with-lock-held ((machine-timeout-lock machine))
    (when (machine-timeout-thread machine)
      (setf (machine-timeout-cancelled machine) t)
      (setf (machine-timeout-thread machine) nil)
      t)))

(defun start-timeout (machine state-name duration trigger)
  "Start a timeout timer for MACHINE.
After DURATION seconds, fires TRIGGER if still in STATE-NAME.
Thread-safe operation. Cancels any existing timeout first."
  (cancel-timeout machine)
  (bt:with-lock-held ((machine-timeout-lock machine))
    (setf (machine-timeout-cancelled machine) nil)
    (setf (machine-timeout-thread machine)
          (bt:make-thread
           (lambda ()
             ;; Sleep for the duration
             (sleep duration)
             ;; Check if we should still fire
             (let ((should-fire nil))
               (bt:with-lock-held ((machine-timeout-lock machine))
                 (unless (machine-timeout-cancelled machine)
                   ;; Only fire if still in the expected state
                   (when (eq (machine-current-state machine) state-name)
                     ;; Clear the thread reference and mark for firing
                     (setf (machine-timeout-thread machine) nil)
                     (setf (machine-timeout-cancelled machine) t)
                     (setf should-fire t))))
               ;; Fire outside the lock to avoid deadlock
               (when should-fire
                 (handler-case
                     (fire machine trigger)
                   (error (e)
                     (declare (ignore e))
                     ;; Ignore errors from firing (e.g., invalid trigger)
                     nil)))))
           :name (format nil "timeout-~A" state-name)))))

(defun setup-state-timeout (machine state-name)
  "Set up timeout for the state if it has one configured.
Looks up the state and starts a timeout if timeout and timeout-trigger are set."
  (let ((state (get-state machine state-name)))
    (when state
      (let ((timeout (state-timeout state))
            (trigger (state-timeout-trigger state)))
        (when (and timeout trigger)
          (start-timeout machine state-name timeout trigger))))))
