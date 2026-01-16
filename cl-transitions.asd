;;;; cl-transitions.asd - ASDF system definition for cl-transitions

(asdf:defsystem #:cl-transitions
  :description "A finite state machine library for Common Lisp, inspired by pytransitions"
  :author "George"
  :license "GPLv3"
  :version "0.1.0"
  :serial t
  :components ((:file "package")
               (:file "conditions")
               (:file "state")
               (:file "transition")
               (:file "event-data")
               (:file "callbacks")
               (:file "machine")
               (:file "triggers")
               (:file "api"))
  :in-order-to ((test-op (test-op #:cl-transitions/tests))))

(asdf:defsystem #:cl-transitions/tests
  :description "Tests for cl-transitions"
  :author "George"
  :license "MIT"
  :depends-on (#:cl-transitions #:fiveam)
  :serial t
  :pathname "t"
  :components ((:file "package")
               (:file "tests"))
  :perform (test-op (op c)
                    (uiop:symbol-call :fiveam :run!
                                      (uiop:find-symbol* :cl-transitions-suite
                                                         :cl-transitions/tests))))
