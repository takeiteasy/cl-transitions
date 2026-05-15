;;;; package.lisp - Package definition for cl-transitions

(defpackage #:cl-transitions
  (:use #:cl)
  (:export
   ;; Conditions
   #:transition-error
   #:invalid-state-error
   #:invalid-trigger-error
   #:condition-failed-error
   #:auto-transition-loop-error

   ;; State class
   #:state
   #:state-name
   #:state-on-enter
   #:state-on-exit
   #:state-timeout
   #:state-timeout-trigger

   ;; Transition class
    #:transition
    #:make-transition
    #:transition-trigger
    #:transition-source
    #:transition-dest
    #:transition-before
    #:transition-after
    #:transition-prepare
    #:transition-conditions
    #:transition-finalize
    #:transition-auto-p
    #:transition-priority
    #:reflexive-dest-p
    #:resolve-transition-dest

   ;; Event-data class
   #:event-data
   #:event-machine
   #:event-model
   #:event-transition
   #:event-source
   #:event-dest
   #:event-args
   #:event-transition-succeeded

   ;; Machine class
   #:machine
   #:machine-model
   #:machine-states
   #:machine-transitions
   #:machine-current-state
   #:machine-initial-state
   #:machine-auto-transitions
   #:machine-ignore-invalid-triggers
   #:machine-max-auto-transitions

   ;; Core protocol
    #:add-state
    #:add-transition
    #:get-state
    #:current-state
    #:set-state

   ;; Introspection
    #:find-transitions
    #:get-triggers

   ;; Triggers
   #:fire
   #:may-fire-p

   ;; High-level API
   #:make-machine
   #:define-machine

   ;; Machine inheritance
   #:copy-state
   #:copy-transition
   #:inherit-states
   #:inherit-transitions
   #:inherit-machine

   ;; Timeout functions
   #:cancel-timeout
   #:start-timeout
   #:setup-state-timeout))
