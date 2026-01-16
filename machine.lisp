;;;; machine.lisp - Machine class for cl-transitions

(in-package #:cl-transitions)

(defclass machine ()
  ((model :initarg :model
          :accessor machine-model
          :initform nil
          :documentation "Optional external model object")
   (states :initarg :states
           :accessor machine-states
           :initform (make-hash-table)
           :documentation "Hash table mapping state names to state objects")
   (transitions :initarg :transitions
                :accessor machine-transitions
                :initform nil
                :type list
                :documentation "List of transition objects")
   (current-state :initarg :current-state
                  :accessor machine-current-state
                  :type symbol
                  :documentation "The current state of the machine")
   (initial-state :initarg :initial-state
                  :accessor machine-initial-state
                  :type symbol
                  :documentation "The initial state of the machine")
   (auto-transitions :initarg :auto-transitions
                     :accessor machine-auto-transitions
                     :initform t
                     :type boolean
                     :documentation "Whether to automatically execute transitions")
   (ignore-invalid-triggers :initarg :ignore-invalid-triggers
                            :accessor machine-ignore-invalid-triggers
                            :initform nil
                            :type boolean
                            :documentation "If T, invalid triggers return NIL instead of signaling an error"))
  (:documentation "The finite state machine controller"))

(defmethod print-object ((machine machine) stream)
  (print-unreadable-object (machine stream :type t :identity t)
    (format stream "state: ~S" (machine-current-state machine))))

(defun add-state (machine state-or-name &key on-enter on-exit)
  "Add a state to the machine.
STATE-OR-NAME can be a state object or a symbol (state name).
Returns the state object."
  (let ((state (etypecase state-or-name
                 (state state-or-name)
                 (symbol (make-state state-or-name
                                     :on-enter on-enter
                                     :on-exit on-exit)))))
    (setf (gethash (state-name state) (machine-states machine)) state)
    state))

(defun add-transition (machine transition)
  "Add a transition to the machine. Returns the transition."
  (push transition (machine-transitions machine))
  transition)

(defun get-state (machine state-name)
  "Get the state object for STATE-NAME, or NIL if not found."
  (gethash state-name (machine-states machine)))

(defun current-state (machine)
  "Get the current state symbol of the machine."
  (machine-current-state machine))

(defun set-state (machine state-name)
  "Set the current state of the machine to STATE-NAME.
Signals INVALID-STATE-ERROR if the state doesn't exist.
Returns the new state name."
  (unless (get-state machine state-name)
    (error 'invalid-state-error
           :machine machine
           :state state-name
           :message (format nil "State ~A does not exist" state-name)))
  (setf (machine-current-state machine) state-name))

(defun find-transitions-for-trigger (machine trigger)
  "Find all transitions matching TRIGGER from the current state.
Returns a list of matching transition objects."
  (let ((current (machine-current-state machine)))
    (remove-if-not (lambda (trans)
                     (and (eq (transition-trigger trans) trigger)
                          (transition-matches-source-p trans current)))
                   (machine-transitions machine))))
