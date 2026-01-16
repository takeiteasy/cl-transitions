;;;; t/tests.lisp - FiveAM tests for cl-transitions

(in-package #:cl-transitions/tests)

(def-suite cl-transitions-suite
  :description "Test suite for cl-transitions")

(in-suite cl-transitions-suite)

(defun run-tests ()
  "Run all cl-transitions tests."
  (run! 'cl-transitions-suite))

;;; ---------------------------------------------------------------------------
;;; State Tests
;;; ---------------------------------------------------------------------------

(def-suite state-tests :in cl-transitions-suite)
(in-suite state-tests)

(test make-state-basic
  "Test basic state creation"
  (let ((state (cl-transitions::make-state :solid)))
    (is (eq :solid (state-name state)))
    (is (null (state-on-enter state)))
    (is (null (state-on-exit state)))))

(test make-state-with-callbacks
  "Test state creation with callbacks"
  (let* ((enter-fn (lambda (e) (declare (ignore e)) :entered))
         (exit-fn (lambda (e) (declare (ignore e)) :exited))
         (state (cl-transitions::make-state :liquid
                                            :on-enter enter-fn
                                            :on-exit exit-fn)))
    (is (eq :liquid (state-name state)))
    (is (= 1 (length (state-on-enter state))))
    (is (= 1 (length (state-on-exit state))))))

;;; ---------------------------------------------------------------------------
;;; Transition Tests
;;; ---------------------------------------------------------------------------

(def-suite transition-tests :in cl-transitions-suite)
(in-suite transition-tests)

(test make-transition-basic
  "Test basic transition creation"
  (let ((trans (cl-transitions::make-transition :melt :solid :liquid)))
    (is (eq :melt (transition-trigger trans)))
    (is (eq :solid (transition-source trans)))
    (is (eq :liquid (transition-dest trans)))
    (is (null (transition-before trans)))
    (is (null (transition-after trans)))
    (is (null (transition-conditions trans)))))

(test make-transition-with-callbacks
  "Test transition creation with callbacks"
  (let* ((before-fn (lambda (e) (declare (ignore e))))
         (after-fn (lambda (e) (declare (ignore e))))
         (trans (cl-transitions::make-transition :melt :solid :liquid
                                                 :before before-fn
                                                 :after after-fn)))
    (is (= 1 (length (transition-before trans))))
    (is (= 1 (length (transition-after trans))))))

(test transition-matches-source-single
  "Test transition source matching with single state"
  (let ((trans (cl-transitions::make-transition :melt :solid :liquid)))
    (is (cl-transitions::transition-matches-source-p trans :solid))
    (is (not (cl-transitions::transition-matches-source-p trans :liquid)))
    (is (not (cl-transitions::transition-matches-source-p trans :gas)))))

(test transition-matches-source-list
  "Test transition source matching with list of states"
  (let ((trans (cl-transitions::make-transition :heat '(:solid :liquid) :gas)))
    (is (cl-transitions::transition-matches-source-p trans :solid))
    (is (cl-transitions::transition-matches-source-p trans :liquid))
    (is (not (cl-transitions::transition-matches-source-p trans :gas)))))

(test transition-matches-source-wildcard
  "Test transition source matching with wildcard"
  (let ((trans (cl-transitions::make-transition :reset :* :initial)))
    (is (cl-transitions::transition-matches-source-p trans :solid))
    (is (cl-transitions::transition-matches-source-p trans :liquid))
    (is (cl-transitions::transition-matches-source-p trans :gas))
    (is (cl-transitions::transition-matches-source-p trans :anything))))

;;; ---------------------------------------------------------------------------
;;; Machine Tests
;;; ---------------------------------------------------------------------------

(def-suite machine-tests :in cl-transitions-suite)
(in-suite machine-tests)

(test make-machine-basic
  "Test basic machine creation"
  (let ((m (make-machine
            :states '(:solid :liquid :gas)
            :initial :solid
            :transitions '((:trigger :melt :source :solid :dest :liquid)))))
    (is (eq :solid (current-state m)))
    (is (eq :solid (machine-initial-state m)))
    (is (= 3 (hash-table-count (machine-states m))))
    (is (= 1 (length (machine-transitions m))))))

(test add-state
  "Test adding states to machine"
  (let ((m (make-machine :states '(:a) :initial :a :transitions nil)))
    (add-state m :b)
    (is (not (null (get-state m :a))))
    (is (not (null (get-state m :b))))
    (is (null (get-state m :c)))))

(test set-state-valid
  "Test setting valid state"
  (let ((m (make-machine :states '(:a :b) :initial :a :transitions nil)))
    (set-state m :b)
    (is (eq :b (current-state m)))))

(test set-state-invalid
  "Test setting invalid state signals error"
  (let ((m (make-machine :states '(:a :b) :initial :a :transitions nil)))
    (signals invalid-state-error
      (set-state m :nonexistent))))

;;; ---------------------------------------------------------------------------
;;; Fire/Trigger Tests
;;; ---------------------------------------------------------------------------

(def-suite trigger-tests :in cl-transitions-suite)
(in-suite trigger-tests)

(test fire-basic
  "Test basic trigger firing"
  (let ((m (make-machine
            :states '(:solid :liquid :gas)
            :initial :solid
            :transitions '((:trigger :melt :source :solid :dest :liquid)
                           (:trigger :boil :source :liquid :dest :gas)))))
    (is (eq :solid (current-state m)))
    (is (eq :liquid (fire m :melt)))
    (is (eq :liquid (current-state m)))
    (is (eq :gas (fire m :boil)))
    (is (eq :gas (current-state m)))))

(test fire-invalid-trigger-error
  "Test that invalid trigger signals error by default"
  (let ((m (make-machine
            :states '(:a :b)
            :initial :a
            :transitions '((:trigger :go :source :a :dest :b)))))
    (signals invalid-trigger-error
      (fire m :invalid))))

(test fire-invalid-trigger-ignored
  "Test that invalid trigger returns NIL when ignored"
  (let ((m (make-machine
            :states '(:a :b)
            :initial :a
            :transitions '((:trigger :go :source :a :dest :b))
            :ignore-invalid-triggers t)))
    (is (null (fire m :invalid)))
    (is (eq :a (current-state m)))))

(test fire-wrong-state
  "Test firing trigger from wrong state"
  (let ((m (make-machine
            :states '(:a :b :c)
            :initial :a
            :transitions '((:trigger :go :source :b :dest :c)))))
    (signals invalid-trigger-error
      (fire m :go))))

(test fire-wildcard-source
  "Test firing with wildcard source"
  (let ((m (make-machine
            :states '(:a :b :c :reset-state)
            :initial :a
            :transitions '((:trigger :go :source :a :dest :b)
                           (:trigger :next :source :b :dest :c)
                           (:trigger :reset :source :* :dest :reset-state)))))
    (fire m :go)
    (is (eq :b (current-state m)))
    (fire m :reset)
    (is (eq :reset-state (current-state m)))))

(test fire-list-source
  "Test firing with list of source states"
  (let ((m (make-machine
            :states '(:a :b :c)
            :initial :a
            :transitions '((:trigger :to-c :source (:a :b) :dest :c)))))
    (is (eq :c (fire m :to-c)))
    (set-state m :b)
    (is (eq :c (fire m :to-c)))))

;;; ---------------------------------------------------------------------------
;;; May-Fire-P Tests
;;; ---------------------------------------------------------------------------

(def-suite may-fire-tests :in cl-transitions-suite)
(in-suite may-fire-tests)

(test may-fire-p-basic
  "Test may-fire-p for valid transitions"
  (let ((m (make-machine
            :states '(:a :b :c)
            :initial :a
            :transitions '((:trigger :go :source :a :dest :b)
                           (:trigger :next :source :b :dest :c)))))
    (is (may-fire-p m :go))
    (is (not (may-fire-p m :next)))
    (is (not (may-fire-p m :invalid)))))

(test may-fire-p-after-transition
  "Test may-fire-p after state change"
  (let ((m (make-machine
            :states '(:a :b :c)
            :initial :a
            :transitions '((:trigger :go :source :a :dest :b)
                           (:trigger :next :source :b :dest :c)))))
    (fire m :go)
    (is (not (may-fire-p m :go)))
    (is (may-fire-p m :next))))

;;; ---------------------------------------------------------------------------
;;; Condition Tests
;;; ---------------------------------------------------------------------------

(def-suite condition-tests :in cl-transitions-suite)
(in-suite condition-tests)

(test conditions-block-transition
  "Test that failing conditions block transition"
  (let* ((allowed nil)
         (check-fn (lambda (e) (declare (ignore e)) allowed))
         (m (make-machine
             :states '(:a :b)
             :initial :a
             :transitions (list (list :trigger :go
                                      :source :a
                                      :dest :b
                                      :conditions (list check-fn))))))
    ;; Condition fails
    (is (null (fire m :go)))
    (is (eq :a (current-state m)))
    (is (not (may-fire-p m :go)))
    ;; Now allow
    (setf allowed t)
    (is (may-fire-p m :go))
    (is (eq :b (fire m :go)))
    (is (eq :b (current-state m)))))

(test multiple-conditions-all-must-pass
  "Test that all conditions must pass"
  (let* ((cond1 t)
         (cond2 t)
         (check1 (lambda (e) (declare (ignore e)) cond1))
         (check2 (lambda (e) (declare (ignore e)) cond2))
         (m (make-machine
             :states '(:a :b)
             :initial :a
             :transitions (list (list :trigger :go
                                      :source :a
                                      :dest :b
                                      :conditions (list check1 check2))))))
    ;; Both pass
    (is (may-fire-p m :go))
    ;; One fails
    (setf cond1 nil)
    (is (not (may-fire-p m :go)))
    ;; Other one fails
    (setf cond1 t cond2 nil)
    (is (not (may-fire-p m :go)))
    ;; Both fail
    (setf cond1 nil)
    (is (not (may-fire-p m :go)))))

;;; ---------------------------------------------------------------------------
;;; Callback Tests
;;; ---------------------------------------------------------------------------

(def-suite callback-tests :in cl-transitions-suite)
(in-suite callback-tests)

(test callback-execution-order
  "Test callbacks execute in correct order"
  (let* ((log nil)
         (prepare-fn (lambda (e) (declare (ignore e)) (push :prepare log)))
         (before-fn (lambda (e) (declare (ignore e)) (push :before log)))
         (on-exit-fn (lambda (e) (declare (ignore e)) (push :on-exit log)))
         (on-enter-fn (lambda (e) (declare (ignore e)) (push :on-enter log)))
         (after-fn (lambda (e) (declare (ignore e)) (push :after log)))
         (m (make-machine
             :states (list (list :name :a :on-exit (list on-exit-fn))
                           (list :name :b :on-enter (list on-enter-fn)))
             :initial :a
             :transitions (list (list :trigger :go
                                      :source :a
                                      :dest :b
                                      :prepare (list prepare-fn)
                                      :before (list before-fn)
                                      :after (list after-fn))))))
    (fire m :go)
    (is (equal '(:prepare :before :on-exit :on-enter :after)
               (reverse log)))))

(test callback-receives-event-data
  "Test callbacks receive correct event data"
  (let* ((captured-event nil)
         (capture-fn (lambda (e) (setf captured-event e)))
         (m (make-machine
             :states '(:a :b)
             :initial :a
             :transitions (list (list :trigger :go
                                      :source :a
                                      :dest :b
                                      :before (list capture-fn))))))
    (fire m :go)
    (is (not (null captured-event)))
    (is (eq :a (event-source captured-event)))
    (is (eq :b (event-dest captured-event)))
    (is (eq m (event-machine captured-event)))))

(test callback-with-model
  "Test callbacks receive model"
  (let* ((my-model (list :data 42))
         (captured-model nil)
         (capture-fn (lambda (e) (setf captured-model (event-model e))))
         (m (make-machine
             :states '(:a :b)
             :initial :a
             :model my-model
             :transitions (list (list :trigger :go
                                      :source :a
                                      :dest :b
                                      :before (list capture-fn))))))
    (fire m :go)
    (is (eq my-model captured-model))))

;;; ---------------------------------------------------------------------------
;;; Define-Machine Macro Tests
;;; ---------------------------------------------------------------------------

(def-suite macro-tests :in cl-transitions-suite)
(in-suite macro-tests)

(test define-machine-basic
  "Test define-machine macro creates machine"
  (let ((result (macroexpand-1
                 '(define-machine test-fsm
                   (:states :a :b :c)
                   (:initial :a)
                   (:transitions
                    (:go :a -> :b)
                    (:next :b -> :c))))))
    (is (eq 'defparameter (first result)))
    (is (eq '*test-fsm* (second result)))))

(test define-machine-functional
  "Test define-machine creates working machine"
  (eval '(define-machine test-matter
          (:states :solid :liquid :gas)
          (:initial :solid)
          (:transitions
           (:melt :solid -> :liquid)
           (:freeze :liquid -> :solid)
           (:boil :liquid -> :gas))))
  (let ((m (symbol-value '*test-matter*)))
    (is (eq :solid (current-state m)))
    (fire m :melt)
    (is (eq :liquid (current-state m)))
    (fire m :boil)
    (is (eq :gas (current-state m)))))

;;; ---------------------------------------------------------------------------
;;; Error Condition Tests
;;; ---------------------------------------------------------------------------

(def-suite error-tests :in cl-transitions-suite)
(in-suite error-tests)

(test invalid-state-error-slots
  "Test invalid-state-error has correct slots"
  (let ((m (make-machine :states '(:a) :initial :a :transitions nil)))
    (handler-case
        (set-state m :nonexistent)
      (invalid-state-error (e)
        (is (eq m (cl-transitions::transition-error-machine e)))
        (is (eq :nonexistent (cl-transitions::invalid-state-error-state e)))))))

(test invalid-trigger-error-slots
  "Test invalid-trigger-error has correct slots"
  (let ((m (make-machine :states '(:a :b) :initial :a
                         :transitions '((:trigger :go :source :b :dest :a)))))
    (handler-case
        (fire m :go)
      (invalid-trigger-error (e)
        (is (eq m (cl-transitions::transition-error-machine e)))
        (is (eq :go (cl-transitions::invalid-trigger-error-trigger e)))
        (is (eq :a (cl-transitions::invalid-trigger-error-current-state e)))))))

;;; ---------------------------------------------------------------------------
;;; Integration Tests
;;; ---------------------------------------------------------------------------

(def-suite integration-tests :in cl-transitions-suite)
(in-suite integration-tests)

(test matter-state-machine
  "Test complete matter state machine example"
  (let ((m (make-machine
            :states '(:solid :liquid :gas :plasma)
            :initial :solid
            :transitions
            '((:trigger :melt :source :solid :dest :liquid)
              (:trigger :freeze :source :liquid :dest :solid)
              (:trigger :boil :source :liquid :dest :gas)
              (:trigger :condense :source :gas :dest :liquid)
              (:trigger :ionize :source :gas :dest :plasma)
              (:trigger :deionize :source :plasma :dest :gas)))))
    ;; Start at solid
    (is (eq :solid (current-state m)))
    ;; Melt to liquid
    (is (eq :liquid (fire m :melt)))
    ;; Can't melt again
    (is (not (may-fire-p m :melt)))
    ;; Can freeze or boil
    (is (may-fire-p m :freeze))
    (is (may-fire-p m :boil))
    ;; Boil to gas
    (is (eq :gas (fire m :boil)))
    ;; Ionize to plasma
    (is (eq :plasma (fire m :ionize)))
    ;; Deionize back to gas
    (is (eq :gas (fire m :deionize)))
    ;; Condense to liquid
    (is (eq :liquid (fire m :condense)))
    ;; Freeze to solid
    (is (eq :solid (fire m :freeze)))))

(test traffic-light-state-machine
  "Test traffic light state machine with timer conditions"
  (let* ((timer 0)
         (green-time 30)
         (yellow-time 5)
         (red-time 25)
         (green-expired (lambda (e) (declare (ignore e)) (>= timer green-time)))
         (yellow-expired (lambda (e) (declare (ignore e)) (>= timer (+ green-time yellow-time))))
         (red-expired (lambda (e) (declare (ignore e)) (>= timer (+ green-time yellow-time red-time))))
         (m (make-machine
             :states '(:green :yellow :red)
             :initial :green
             :transitions
             (list (list :trigger :tick :source :green :dest :yellow
                         :conditions (list green-expired))
                   (list :trigger :tick :source :yellow :dest :red
                         :conditions (list yellow-expired))
                   (list :trigger :tick :source :red :dest :green
                         :conditions (list red-expired))))))
    ;; Start green
    (is (eq :green (current-state m)))
    ;; Tick doesn't change until timer expires
    (is (null (fire m :tick)))
    (is (eq :green (current-state m)))
    ;; Advance timer past green
    (setf timer 30)
    (is (eq :yellow (fire m :tick)))
    ;; Advance timer past yellow
    (setf timer 35)
    (is (eq :red (fire m :tick)))
    ;; Advance timer past red
    (setf timer 60)
    (is (eq :green (fire m :tick)))))
