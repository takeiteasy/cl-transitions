;;;; transition.lisp - Transition class for cl-transitions

(in-package #:cl-transitions)

(defclass transition ()
  ((trigger :initarg :trigger
            :accessor transition-trigger
            :type symbol
            :documentation "The trigger symbol that activates this transition")
   (source :initarg :source
           :accessor transition-source
           :type (or symbol list)
           :documentation "Source state(s): a symbol, list of symbols, or :* for any")
   (dest :initarg :dest
         :accessor transition-dest
         :type symbol
         :documentation "Destination state symbol")
   (before :initarg :before
           :accessor transition-before
           :initform nil
           :type list
           :documentation "Callbacks to invoke before the transition")
   (after :initarg :after
          :accessor transition-after
          :initform nil
          :type list
          :documentation "Callbacks to invoke after the transition")
   (prepare :initarg :prepare
            :accessor transition-prepare
            :initform nil
            :type list
            :documentation "Callbacks to invoke to prepare for the transition")
   (conditions :initarg :conditions
               :accessor transition-conditions
               :initform nil
               :type list
               :documentation "Guard predicates that must all return true"))
  (:documentation "Represents a transition between states in the FSM"))

(defmethod print-object ((trans transition) stream)
  (print-unreadable-object (trans stream :type t :identity t)
    (format stream "~S: ~S -> ~S"
            (transition-trigger trans)
            (transition-source trans)
            (transition-dest trans))))

(defun ensure-list (x)
  "Ensure X is a list. If X is NIL, return NIL. If X is not a list, wrap it."
  (cond ((null x) nil)
        ((listp x) x)
        (t (list x))))

(defun make-transition (trigger source dest &key before after prepare conditions)
  "Create a new transition with the given parameters."
  (make-instance 'transition
                 :trigger trigger
                 :source source
                 :dest dest
                 :before (ensure-list before)
                 :after (ensure-list after)
                 :prepare (ensure-list prepare)
                 :conditions (ensure-list conditions)))

(defun transition-matches-source-p (transition current-state)
  "Check if TRANSITION can be triggered from CURRENT-STATE.
Returns T if source is :* (wildcard), matches exactly, or is in source list."
  (let ((source (transition-source transition)))
    (cond
      ((eq source :*) t)
      ((listp source) (member current-state source))
      (t (eq source current-state)))))
