;;;; conditions.lisp - Error conditions for cl-transitions

(in-package #:cl-transitions)

(define-condition transition-error (error)
  ((machine :initarg :machine :reader transition-error-machine)
   (message :initarg :message :reader transition-error-message))
  (:report (lambda (condition stream)
             (format stream "Transition error: ~A"
                     (transition-error-message condition)))))

(define-condition invalid-state-error (transition-error)
  ((state :initarg :state :reader invalid-state-error-state))
  (:report (lambda (condition stream)
             (format stream "Invalid state: ~A"
                     (invalid-state-error-state condition)))))

(define-condition invalid-trigger-error (transition-error)
  ((trigger :initarg :trigger :reader invalid-trigger-error-trigger)
   (current-state :initarg :current-state :reader invalid-trigger-error-current-state))
  (:report (lambda (condition stream)
             (format stream "Invalid trigger ~A from state ~A"
                     (invalid-trigger-error-trigger condition)
                     (invalid-trigger-error-current-state condition)))))

(define-condition condition-failed-error (transition-error)
  ((trigger :initarg :trigger :reader condition-failed-error-trigger)
   (condition-fn :initarg :condition-fn :reader condition-failed-error-condition-fn))
  (:report (lambda (condition stream)
             (format stream "Condition ~A failed for trigger ~A"
                     (condition-failed-error-condition-fn condition)
                     (condition-failed-error-trigger condition)))))

(define-condition auto-transition-loop-error (transition-error)
  ((depth :initarg :depth :reader auto-transition-loop-error-depth)
   (max-depth :initarg :max-depth :reader auto-transition-loop-error-max-depth))
  (:report (lambda (condition stream)
             (format stream "Auto-transition loop detected: depth ~A exceeds max ~A"
                     (auto-transition-loop-error-depth condition)
                     (auto-transition-loop-error-max-depth condition)))))
