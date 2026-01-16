;;;; t/package.lisp - Test package for cl-transitions

(defpackage #:cl-transitions/tests
  (:use #:cl #:cl-transitions #:fiveam)
  (:export #:cl-transitions-suite
           #:run-tests))
