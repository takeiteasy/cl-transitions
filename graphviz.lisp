;;;; graphviz.lisp - Graphviz export for cl-transitions using cl-dot

(defpackage #:cl-transitions/graphviz
  (:use #:cl #:cl-transitions)
  (:import-from #:cl-dot
                #:node
                #:generate-graph-from-roots
                #:print-graph
                #:graph-object-node
                #:graph-object-edges
                #:graph-object-knows-of)
  (:export
   #:machine->dot
   #:write-dot
   #:draw
   #:*dot-path*
   #:fsm-graph
   #:fsm-machine))

(in-package #:cl-transitions/graphviz)

(defvar *dot-path* nil
  "Path to the Graphviz dot executable. If NIL, searches PATH.")

(defclass fsm-graph ()
  ((machine :initarg :machine :accessor fsm-machine))
  (:documentation "Graph context for the cl-dot protocol."))

(defun node-attrs (g state)
  (let* ((name (state-name state))
         (machine (fsm-machine g))
         (initial (and (machine-initial-state machine)
                       (eq name (machine-initial-state machine))))
         (current (and (machine-current-state machine)
                       (eq name (machine-current-state machine))))
         (fill (cond (current "#B4D8FF")
                     (initial "#E8FFE8")
                     (t "#F0F0F0"))))
    `(:label ,(string-downcase name) :fontname "Monospace"
      :fontsize 11 :shape :box :style (:rounded :filled)
      :fillcolor ,fill
      ,@(when initial (list :peripheries 2)))))

(defun resolve-sources (table source)
  (cond ((eq source :*)
         (let (all)
           (maphash (lambda (k v) (declare (ignore k)) (push v all)) table)
           (nreverse all)))
        ((listp source)
         (loop for s in source for state = (gethash s table) when state collect state))
        (t
         (let ((state (gethash source table)))
           (when state (list state))))))

(defun edge-attrs (trans)
  `(:label ,(string-downcase (transition-trigger trans))
    :fontname "Monospace" :fontsize 9
    :style ,(if (transition-auto-p trans) :dashed :solid)
    :arrowhead :normal
    :arrowtail :none))

(defmethod graph-object-node ((g fsm-graph) (machine machine))
  nil)

(defmethod graph-object-knows-of ((g fsm-graph) (machine machine))
  (let (states)
    (maphash (lambda (name state) (declare (ignore name)) (push state states))
             (machine-states machine))
    (nreverse states)))

(defmethod graph-object-node ((g fsm-graph) (state state))
  (make-instance 'node
    :id (state-name state)
    :attributes (node-attrs g state)))

(defmethod graph-object-edges ((g fsm-graph))
  (let* ((machine (fsm-machine g))
         (table (machine-states machine)))
    (loop for trans in (machine-transitions machine)
          for sources = (resolve-sources table (transition-source trans))
          for is-reflexive = (reflexive-dest-p (transition-dest trans))
          for dest = (unless is-reflexive
                       (gethash (transition-dest trans) table))
          append (loop for src in sources
                       for d = (if is-reflexive src dest)
                       when (and src d)
                       collect (list src d (edge-attrs trans))))))

(defun make-graph (machine)
  (generate-graph-from-roots (make-instance 'fsm-graph :machine machine)
                             (list machine)
                             '(:rankdir "LR" :fontname "Monospace" :fontsize 11
                               :splines "true" :overlap "false" :pad 0.5)))

(defun machine->dot (machine)
  "Generate a DOT string representation of MACHINE's state diagram."
  (with-output-to-string (s)
    (print-graph (make-graph machine) :stream s :directed t)))

(defun write-dot (machine pathname)
  "Write DOT representation of MACHINE to PATHNAME.
PATHNAME should be a pathname or string."
  (with-open-file (s pathname :direction :output :if-exists :supersede)
    (print-graph (make-graph machine) :stream s :directed t)))

(defun find-dot ()
  (or (uiop:getenv "CL_DOT_DOT")
      (ignore-errors
        (string-trim '(#\newline #\space)
                     (uiop:run-program '("which" "dot")
                                       :output '(:string :stripped t)
                                       :ignore-error-status t)))
      (probe-file "/usr/local/bin/dot")
      (probe-file "/opt/local/bin/dot")
      (probe-file "/usr/bin/dot")))

(defun draw (machine pathname &key (format "png"))
  "Render MACHINE's state diagram to an image at PATHNAME.
Requires Graphviz dot to be installed.
FORMAT is the output format string (e.g. \"png\", \"svg\", \"pdf\")."
  (let ((dot-exe (or *dot-path* (find-dot)
                     (error "Graphviz ~S executable not found. Install Graphviz or set cl-transitions/graphviz:*dot-path*." "dot")))
        (dot-string (machine->dot machine)))
    (uiop:with-temporary-file (:stream s :pathname p :type "dot")
      (write-string dot-string s)
      (finish-output s)
      (uiop:run-program (list dot-exe (format nil "-T~(~A~)" format)
                               (namestring p) "-o" (namestring pathname))
                        :output t))))
