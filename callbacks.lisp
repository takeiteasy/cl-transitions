;;;; callbacks.lisp - Callback invocation for cl-transitions

(in-package #:cl-transitions)

(defun invoke-callback (callback event-data)
  "Invoke a single callback with the event-data.
CALLBACK can be a function or a symbol naming a function.
Returns the result of the callback invocation."
  (let ((fn (etypecase callback
              (function callback)
              (symbol (symbol-function callback)))))
    (funcall fn event-data)))

(defun invoke-callbacks (callbacks event-data)
  "Invoke a list of callbacks in order with the event-data.
Returns a list of all callback results."
  (mapcar (lambda (cb) (invoke-callback cb event-data)) callbacks))

(defun check-conditions (conditions event-data)
  "Check all condition predicates against event-data.
Returns T if all conditions pass (or if there are no conditions).
Returns NIL on the first condition that returns NIL."
  (every (lambda (condition)
           (invoke-callback condition event-data))
         conditions))
