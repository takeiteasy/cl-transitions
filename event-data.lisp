;;;; event-data.lisp - Event data class for cl-transitions

(in-package #:cl-transitions)

(defclass event-data ()
  ((machine :initarg :machine
            :accessor event-machine
            :documentation "The machine instance")
   (model :initarg :model
          :accessor event-model
          :initform nil
          :documentation "The optional model object associated with the machine")
   (transition :initarg :transition
               :accessor event-transition
               :documentation "The transition being executed")
   (source :initarg :source
           :accessor event-source
           :type symbol
           :documentation "The source state")
   (dest :initarg :dest
         :accessor event-dest
         :type symbol
         :documentation "The destination state")
   (args :initarg :args
         :accessor event-args
         :initform nil
         :type list
         :documentation "Additional arguments passed to fire")
   (transition-succeeded :initarg :transition-succeeded
                         :accessor event-transition-succeeded
                         :initform t
                         :type boolean
                         :documentation "Whether the transition succeeded (T) or failed (NIL)"))
  (:documentation "Data passed to callbacks during transition execution"))

(defmethod print-object ((event event-data) stream)
  (print-unreadable-object (event stream :type t :identity t)
    (format stream "~S -> ~S"
            (event-source event)
            (event-dest event))))

(defun make-event-data (machine transition source dest &optional args)
  "Create a new event-data instance for callback invocation."
  (make-instance 'event-data
                 :machine machine
                 :model (slot-value machine 'model)
                 :transition transition
                 :source source
                 :dest dest
                 :args args))
