;;;; api.lisp - High-level API for cl-transitions

(in-package #:cl-transitions)

(defun parse-state-spec (spec)
  "Parse a state specification into (name on-enter on-exit timeout timeout-trigger).
SPEC can be:
  - A symbol: (:solid) -> (:solid nil nil nil nil)
  - A plist: (:name :solid :on-enter (fn) :timeout 5 :timeout-trigger :expire)"
  (etypecase spec
    (symbol (list spec nil nil nil nil))
    (list (if (keywordp (first spec))
              ;; Plist form: (:name :solid :on-enter ...)
              (list (getf spec :name)
                    (ensure-list (getf spec :on-enter))
                    (ensure-list (getf spec :on-exit))
                    (getf spec :timeout)
                    (getf spec :timeout-trigger))
              ;; Could also be a list starting with name
              (list (first spec)
                    (ensure-list (getf (rest spec) :on-enter))
                    (ensure-list (getf (rest spec) :on-exit))
                    (getf (rest spec) :timeout)
                    (getf (rest spec) :timeout-trigger))))))

(defun parse-transition-spec (spec)
  "Parse a transition specification into a property list.
SPEC should be a plist with :trigger, :source, :dest, and optional callbacks."
  (list :trigger (getf spec :trigger)
        :source (getf spec :source)
        :dest (getf spec :dest)
        :before (ensure-list (getf spec :before))
        :after (ensure-list (getf spec :after))
        :prepare (ensure-list (getf spec :prepare))
        :conditions (ensure-list (getf spec :conditions))
        :finalize (ensure-list (getf spec :finalize))
        :auto (getf spec :auto)))

(defun make-machine (&key states initial transitions model
                       (auto-transitions t)
                       (ignore-invalid-triggers nil)
                       (max-auto-transitions 10)
                       inherit-from
                       (inherit-override t))
  "Create a new state machine.

STATES is a list of state specifications. Each can be:
  - A symbol: :solid
  - A plist: (:name :solid :on-enter (fn1) :on-exit (fn2))

INITIAL is the initial state symbol.

TRANSITIONS is a list of transition specifications, each a plist:
  (:trigger :melt :source :solid :dest :liquid
   :before (fn) :after (fn) :prepare (fn) :conditions (pred) :finalize (fn) :auto t)

MODEL is an optional external object to associate with the machine.

AUTO-TRANSITIONS (default T) controls automatic transition execution.

IGNORE-INVALID-TRIGGERS (default NIL) if T, invalid triggers return NIL
instead of signaling an error.

MAX-AUTO-TRANSITIONS (default 10) maximum auto-transition chain depth.

INHERIT-FROM if provided, inherits states and transitions from this parent machine.

INHERIT-OVERRIDE (default T) if T, child definitions override parent definitions.

Returns the new machine instance."
  (let ((machine (make-instance 'machine
                                :model model
                                :initial-state initial
                                :current-state initial
                                :auto-transitions auto-transitions
                                :ignore-invalid-triggers ignore-invalid-triggers
                                :max-auto-transitions max-auto-transitions)))
    ;; Add states
    (dolist (state-spec states)
      (destructuring-bind (name on-enter on-exit timeout timeout-trigger)
          (parse-state-spec state-spec)
        (add-state machine name
                   :on-enter on-enter
                   :on-exit on-exit
                   :timeout timeout
                   :timeout-trigger timeout-trigger)))
    ;; Add transitions
    (dolist (trans-spec transitions)
      (let ((parsed (parse-transition-spec trans-spec)))
        (add-transition machine
                        (make-transition (getf parsed :trigger)
                                         (getf parsed :source)
                                         (getf parsed :dest)
                                         :before (getf parsed :before)
                                         :after (getf parsed :after)
                                         :prepare (getf parsed :prepare)
                                         :conditions (getf parsed :conditions)
                                         :finalize (getf parsed :finalize)
                                         :auto (getf parsed :auto)))))
    ;; Inherit from parent if specified
    (when inherit-from
      (inherit-machine machine inherit-from :override inherit-override))
    ;; Set up timeout for initial state
    (when initial
      (setup-state-timeout machine initial))
    machine))

(defun arrow-symbol-p (sym)
  "Check if SYM is an arrow symbol (-> in any package)."
  (and (symbolp sym)
       (string= (symbol-name sym) "->")))

(defun parse-define-transition (spec)
  "Parse a define-machine transition spec: (:trigger :source -> :dest ...)
Returns (trigger source dest options)."
  (let* ((trigger (first spec))
         (rest (rest spec))
         (arrow-pos (position-if #'arrow-symbol-p rest))
         (source (if arrow-pos
                     (if (= arrow-pos 1)
                         (first rest)
                         (subseq rest 0 arrow-pos))
                     (first rest)))
         (after-arrow (if arrow-pos
                          (nthcdr (1+ arrow-pos) rest)
                          (rest rest)))
         (dest (first after-arrow))
         (options (rest after-arrow)))
    (list trigger source dest options)))

(defmacro define-machine (name &body clauses)
  "Define a state machine and bind it to *NAME*.

Syntax:
  (define-machine name
    (:states :solid :liquid :gas)
    (:initial :solid)
    (:inherit *parent-machine*)           ; optional inheritance
    (:transitions
     (:melt :solid -> :liquid)
     (:freeze :liquid -> :solid)
     (:boil :liquid -> :gas :before (fn) :after (fn))))

Each transition can have optional :before, :after, :prepare, :conditions, :finalize, :auto.
The arrow -> separates source from destination.
Source can be a single state, a list of states, or :* for wildcard."
  (let ((states-clause (find :states clauses :key #'first))
        (initial-clause (find :initial clauses :key #'first))
        (transitions-clause (find :transitions clauses :key #'first))
        (model-clause (find :model clauses :key #'first))
        (options-clause (find :options clauses :key #'first))
        (inherit-clause (find :inherit clauses :key #'first)))
    (let ((states (rest states-clause))
          (initial (second initial-clause))
          (transitions (rest transitions-clause))
          (model (second model-clause))
          (ignore-invalid (getf (rest options-clause) :ignore-invalid-triggers))
          (inherit-from (second inherit-clause))
          (inherit-override (if inherit-clause
                                (getf (cddr inherit-clause) :override t)
                                t)))
      `(defparameter ,(intern (format nil "*~A*" name))
         (make-machine
          :states ',(mapcar (lambda (s) (if (symbolp s) s s)) states)
          :initial ',initial
          :transitions
          (list
           ,@(mapcar
              (lambda (trans-spec)
                (destructuring-bind (trigger source dest options)
                    (parse-define-transition trans-spec)
                  `(list :trigger ',trigger
                         :source ',(if (and (listp source)
                                            (not (eq (first source) 'quote)))
                                       source
                                       source)
                         :dest ',dest
                         ,@(when (getf options :before)
                             `(:before ,(getf options :before)))
                         ,@(when (getf options :after)
                             `(:after ,(getf options :after)))
                         ,@(when (getf options :prepare)
                             `(:prepare ,(getf options :prepare)))
                         ,@(when (getf options :conditions)
                             `(:conditions ,(getf options :conditions)))
                         ,@(when (getf options :finalize)
                             `(:finalize ,(getf options :finalize)))
                         ,@(when (getf options :auto)
                             `(:auto ,(getf options :auto))))))
              transitions))
          ,@(when model `(:model ,model))
          ,@(when ignore-invalid `(:ignore-invalid-triggers ,ignore-invalid))
          ,@(when inherit-from `(:inherit-from ,inherit-from))
          ,@(when inherit-clause `(:inherit-override ,inherit-override)))))))
