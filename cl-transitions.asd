;;;; cl-transitions.asd - ASDF system definition for cl-transitions

(asdf:defsystem #:cl-transitions
  :description "Common Lisp port of pytransitions/transitions"
  :author "George Watson"
  :license "GPLv3"
  :version "0.1.0"
  :depends-on (#:bordeaux-threads)
  :serial t
  :components ((:file "package")
               (:file "conditions")
               (:file "state")
               (:file "transition")
               (:file "event-data")
               (:file "callbacks")
               (:file "machine")
               (:file "timeouts")
               (:file "triggers")
               (:file "api"))
  :in-order-to ((test-op (test-op #:cl-transitions/tests))))

(asdf:defsystem #:cl-transitions/graphviz
  :description "Graphviz export for cl-transitions"
  :author "George Watson"
  :license "GPLv3"
  :depends-on (#:cl-transitions #:cl-dot)
  :serial t
  :components ((:file "graphviz")))

(asdf:defsystem #:cl-transitions/tests
  :description "Tests for cl-transitions"
  :author "George Watson"
  :license "GPLv3"
  :depends-on (#:cl-transitions #:cl-transitions/graphviz #:fiveam)
  :serial t
  :pathname "t"
  :components ((:file "package")
               (:file "tests")
               (:file "graphviz"))
  :perform (test-op (op c)
                    (uiop:symbol-call :fiveam :run!
                                      (uiop:find-symbol* :cl-transitions-suite
                                                         :cl-transitions/tests))))
