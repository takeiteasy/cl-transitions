;;;; package.lisp - Package definition for cl-transitions

(defpackage #:cl-transitions
  (:use #:cl)
  (:export
   ;; Conditions
   #:transition-error
   #:invalid-state-error
   #:invalid-trigger-error
   #:condition-failed-error

   ;; State class
   #:state
   #:state-name
   #:state-on-enter
   #:state-on-exit

   ;; Transition class
   #:transition
   #:transition-trigger
   #:transition-source
   #:transition-dest
   #:transition-before
   #:transition-after
   #:transition-prepare
   #:transition-conditions

   ;; Event-data class
   #:event-data
   #:event-machine
   #:event-model
   #:event-transition
   #:event-source
   #:event-dest
   #:event-args

   ;; Machine class
   #:machine
   #:machine-model
   #:machine-states
   #:machine-transitions
   #:machine-current-state
   #:machine-initial-state
   #:machine-auto-transitions
   #:machine-ignore-invalid-triggers

   ;; Core protocol
   #:add-state
   #:add-transition
   #:get-state
   #:current-state
   #:set-state

   ;; Triggers
   #:fire
   #:may-fire-p

   ;; High-level API
   #:make-machine
   #:define-machine))
