;;;; state.lisp - State class for cl-transitions

(in-package #:cl-transitions)

(defclass state ()
  ((name :initarg :name
         :accessor state-name
         :type symbol
         :documentation "The symbolic name of this state")
   (on-enter :initarg :on-enter
             :accessor state-on-enter
             :initform nil
             :type list
             :documentation "List of callbacks to invoke when entering this state")
   (on-exit :initarg :on-exit
            :accessor state-on-exit
            :initform nil
            :type list
            :documentation "List of callbacks to invoke when exiting this state")
   (timeout :initarg :timeout
            :accessor state-timeout
            :initform nil
            :documentation "Timeout duration in seconds, or NIL for no timeout")
   (timeout-trigger :initarg :timeout-trigger
                    :accessor state-timeout-trigger
                    :initform nil
                    :type (or symbol null)
                    :documentation "Trigger to fire when timeout expires"))
  (:documentation "Represents a state in the finite state machine"))

(defmethod print-object ((state state) stream)
  (print-unreadable-object (state stream :type t :identity t)
    (format stream "~S" (state-name state))))

(defun make-state (name &key on-enter on-exit timeout timeout-trigger)
  "Create a new state with the given name and optional callbacks.
TIMEOUT is the duration in seconds before TIMEOUT-TRIGGER is fired."
  (make-instance 'state
                 :name name
                 :on-enter (if (listp on-enter) on-enter (list on-enter))
                 :on-exit (if (listp on-exit) on-exit (list on-exit))
                 :timeout timeout
                 :timeout-trigger timeout-trigger))
