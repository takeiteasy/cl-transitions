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

;;; ---------------------------------------------------------------------------
;;; Reflexive Transition Tests
;;; ---------------------------------------------------------------------------

(def-suite reflexive-tests :in cl-transitions-suite)
(in-suite reflexive-tests)

(test reflexive-stays-in-state
  "Test reflexive transition stays in same state"
  (let ((m (make-machine
            :states '(:a)
            :initial :a
            :transitions '((:trigger :update :source :a :dest :=)))))
    (is (eq :a (current-state m)))
    (fire m :update)
    (is (eq :a (current-state m)))))

(test reflexive-with-same-keyword
  "Test :same keyword works like :="
  (let ((m (make-machine
            :states '(:a)
            :initial :a
            :transitions '((:trigger :update :source :a :dest :same)))))
    (is (eq :a (current-state m)))
    (fire m :update)
    (is (eq :a (current-state m)))))

(test reflexive-skips-on-enter-on-exit
  "Test reflexive transition skips on-enter/on-exit callbacks"
  (let* ((log nil)
         (on-enter-fn (lambda (e) (declare (ignore e)) (push :on-enter log)))
         (on-exit-fn (lambda (e) (declare (ignore e)) (push :on-exit log)))
         (before-fn (lambda (e) (declare (ignore e)) (push :before log)))
         (after-fn (lambda (e) (declare (ignore e)) (push :after log)))
         (m (make-machine
             :states (list (list :name :a
                                 :on-enter (list on-enter-fn)
                                 :on-exit (list on-exit-fn)))
             :initial :a
             :transitions (list (list :trigger :update
                                      :source :a
                                      :dest :=
                                      :before (list before-fn)
                                      :after (list after-fn))))))
    (fire m :update)
    ;; on-enter and on-exit should NOT be in the log
    (is (null (member :on-enter log)))
    (is (null (member :on-exit log)))
    ;; but before and after should be
    (is (member :before log))
    (is (member :after log))))

(test reflexive-dest-p-function
  "Test reflexive-dest-p helper function"
  (is (reflexive-dest-p :=))
  (is (reflexive-dest-p :same))
  (is (reflexive-dest-p :internal))
  (is (not (reflexive-dest-p :other-state)))
  (is (not (reflexive-dest-p nil))))

;;; ---------------------------------------------------------------------------
;;; Finalize Callback Tests
;;; ---------------------------------------------------------------------------

(def-suite finalize-tests :in cl-transitions-suite)
(in-suite finalize-tests)

(test finalize-runs-on-success
  "Test finalize callback runs on successful transition"
  (let* ((finalized nil)
         (finalize-fn (lambda (e)
                        (declare (ignore e))
                        (setf finalized t)))
         (m (make-machine
             :states '(:a :b)
             :initial :a
             :transitions (list (list :trigger :go
                                      :source :a
                                      :dest :b
                                      :finalize (list finalize-fn))))))
    (fire m :go)
    (is (eq t finalized))
    (is (eq :b (current-state m)))))

(test finalize-runs-on-condition-failure
  "Test finalize callback runs when conditions fail"
  (let* ((finalized nil)
         (succeeded nil)
         (finalize-fn (lambda (e)
                        (setf finalized t)
                        (setf succeeded (event-transition-succeeded e))))
         (m (make-machine
             :states '(:a :b)
             :initial :a
             :transitions (list (list :trigger :go
                                      :source :a
                                      :dest :b
                                      :conditions (list (constantly nil))
                                      :finalize (list finalize-fn))))))
    (fire m :go)
    (is (eq t finalized))
    (is (null succeeded))
    (is (eq :a (current-state m)))))

(test finalize-detects-success
  "Test finalize can detect success via event-transition-succeeded"
  (let* ((success-value nil)
         (finalize-fn (lambda (e)
                        (setf success-value (event-transition-succeeded e))))
         (m (make-machine
             :states '(:a :b)
             :initial :a
             :transitions (list (list :trigger :go
                                      :source :a
                                      :dest :b
                                      :finalize (list finalize-fn))))))
    (fire m :go)
    (is (eq t success-value))))

(test multiple-finalize-callbacks
  "Test multiple finalize callbacks all run"
  (let* ((count 0)
         (fn1 (lambda (e) (declare (ignore e)) (incf count)))
         (fn2 (lambda (e) (declare (ignore e)) (incf count)))
         (fn3 (lambda (e) (declare (ignore e)) (incf count)))
         (m (make-machine
             :states '(:a :b)
             :initial :a
             :transitions (list (list :trigger :go
                                      :source :a
                                      :dest :b
                                      :finalize (list fn1 fn2 fn3))))))
    (fire m :go)
    (is (= 3 count))))

;;; ---------------------------------------------------------------------------
;;; Auto-Transition Tests
;;; ---------------------------------------------------------------------------

(def-suite auto-transition-tests :in cl-transitions-suite)
(in-suite auto-transition-tests)

(test auto-transition-fires-on-entry
  "Test auto-transition fires when entering state"
  (let ((m (make-machine
            :states '(:a :b :c)
            :initial :a
            :transitions (list '(:trigger :go :source :a :dest :b)
                               (list :trigger :auto-go :source :b :dest :c :auto t)))))
    (is (eq :a (current-state m)))
    (fire m :go)
    ;; Should have auto-transitioned from :b to :c
    (is (eq :c (current-state m)))))

(test auto-transition-chain
  "Test chain of auto-transitions (a->b->c->d)"
  (let ((m (make-machine
            :states '(:a :b :c :d)
            :initial :a
            :transitions (list '(:trigger :start :source :a :dest :b)
                               (list :trigger :auto1 :source :b :dest :c :auto t)
                               (list :trigger :auto2 :source :c :dest :d :auto t)))))
    (fire m :start)
    (is (eq :d (current-state m)))))

(test auto-transition-respects-conditions
  "Test auto-transition respects conditions"
  (let* ((allowed nil)
         (check-fn (lambda (e) (declare (ignore e)) allowed))
         (m (make-machine
             :states '(:a :b :c)
             :initial :a
             :transitions (list '(:trigger :go :source :a :dest :b)
                                (list :trigger :auto-go :source :b :dest :c
                                      :auto t
                                      :conditions (list check-fn))))))
    (fire m :go)
    ;; Auto-transition should not fire because condition is false
    (is (eq :b (current-state m)))
    ;; Now allow and trigger manually
    (setf allowed t)
    (fire m :auto-go)
    (is (eq :c (current-state m)))))

(test auto-transition-loop-prevention
  "Test infinite loop prevention for auto-transitions"
  (let ((m (make-machine
            :states '(:a :b)
            :initial :a
            :max-auto-transitions 3
            :transitions (list '(:trigger :start :source :a :dest :b)
                               (list :trigger :loop1 :source :b :dest :a :auto t)
                               (list :trigger :loop2 :source :a :dest :b :auto t)))))
    (signals auto-transition-loop-error
      (fire m :start))))

(test auto-transition-callbacks-execute
  "Test auto-transition callbacks execute properly"
  (let* ((log nil)
         (before-fn (lambda (e) (declare (ignore e)) (push :before log)))
         (after-fn (lambda (e) (declare (ignore e)) (push :after log)))
         (m (make-machine
             :states '(:a :b :c)
             :initial :a
             :transitions (list '(:trigger :go :source :a :dest :b)
                                (list :trigger :auto-go :source :b :dest :c
                                      :auto t
                                      :before (list before-fn)
                                      :after (list after-fn))))))
    (fire m :go)
    (is (member :before log))
    (is (member :after log))))

;;; ---------------------------------------------------------------------------
;;; Machine Inheritance Tests
;;; ---------------------------------------------------------------------------

(def-suite inheritance-tests :in cl-transitions-suite)
(in-suite inheritance-tests)

(test basic-state-inheritance
  "Test basic state inheritance"
  (let* ((parent (make-machine
                  :states '(:a :b)
                  :initial :a
                  :transitions nil))
         (child (make-machine
                 :states '(:c)
                 :initial :a
                 :transitions nil
                 :inherit-from parent)))
    ;; Child should have all parent states plus its own
    (is (not (null (get-state child :a))))
    (is (not (null (get-state child :b))))
    (is (not (null (get-state child :c))))))

(test basic-transition-inheritance
  "Test basic transition inheritance"
  (let* ((parent (make-machine
                  :states '(:a :b)
                  :initial :a
                  :transitions '((:trigger :go :source :a :dest :b))))
         (child (make-machine
                 :states nil
                 :initial :a
                 :transitions nil
                 :inherit-from parent)))
    ;; Child should be able to use parent's transition
    (fire child :go)
    (is (eq :b (current-state child)))))

(test child-overrides-parent
  "Test child definitions override parent (default)"
  (let* ((parent-log nil)
         (child-log nil)
         (parent-fn (lambda (e) (declare (ignore e)) (push :parent parent-log)))
         (child-fn (lambda (e) (declare (ignore e)) (push :child child-log)))
         (parent (make-machine
                  :states (list (list :name :a :on-enter (list parent-fn)))
                  :initial :a
                  :transitions nil))
         (child (make-machine
                 :states (list (list :name :a :on-enter (list child-fn)))
                 :initial :a
                 :transitions nil
                 :inherit-from parent)))
    ;; Child's state definition should be used, not parent's
    ;; When we fire a transition that enters :a, child's callback should run
    (add-state child :b)
    (add-transition child (cl-transitions::make-transition :go :b :a))
    (set-state child :b)
    (fire child :go)
    (is (member :child child-log))
    (is (null parent-log))))

(test inherited-machine-is-independent
  "Test inherited machine is independent from parent"
  (let* ((parent (make-machine
                  :states '(:a :b)
                  :initial :a
                  :transitions '((:trigger :go :source :a :dest :b))))
         (child (make-machine
                 :states nil
                 :initial :a
                 :transitions nil
                 :inherit-from parent)))
    ;; Fire transition on child
    (fire child :go)
    (is (eq :b (current-state child)))
    ;; Parent should still be at :a
    (is (eq :a (current-state parent)))))

(test copy-state-function
  "Test copy-state creates independent copy"
  (let* ((original (cl-transitions::make-state :test
                                               :on-enter (list #'identity)
                                               :on-exit (list #'identity)))
         (copied (copy-state original)))
    (is (eq :test (state-name copied)))
    (is (= 1 (length (state-on-enter copied))))
    (is (= 1 (length (state-on-exit copied))))
    ;; Should be different objects
    (is (not (eq original copied)))))

(test copy-transition-function
  "Test copy-transition creates independent copy"
  (let* ((original (cl-transitions::make-transition :go :a :b
                                                    :before (list #'identity)
                                                    :after (list #'identity)))
         (copied (copy-transition original)))
    (is (eq :go (transition-trigger copied)))
    (is (eq :a (transition-source copied)))
    (is (eq :b (transition-dest copied)))
    ;; Should be different objects
    (is (not (eq original copied)))))

;;; ---------------------------------------------------------------------------
;;; Timeout Transition Tests
;;; ---------------------------------------------------------------------------

(def-suite timeout-tests :in cl-transitions-suite)
(in-suite timeout-tests)

(test state-with-timeout-slots
  "Test state can have timeout and timeout-trigger slots"
  (let ((state (cl-transitions::make-state :waiting
                                           :timeout 5
                                           :timeout-trigger :done)))
    (is (= 5 (state-timeout state)))
    (is (eq :done (state-timeout-trigger state)))))

(test states-without-timeout
  "Test states without timeout work normally"
  (let ((m (make-machine
            :states '(:a :b)
            :initial :a
            :transitions '((:trigger :go :source :a :dest :b)))))
    (fire m :go)
    (is (eq :b (current-state m)))))

(test timeout-fires-after-duration
  "Test timeout fires after specified duration"
  (let ((m (make-machine
            :states (list (list :name :waiting :timeout 0.1 :timeout-trigger :done)
                          :finished)
            :initial :waiting
            :transitions '((:trigger :done :source :waiting :dest :finished)))))
    (is (eq :waiting (current-state m)))
    ;; Wait for timeout to fire
    (sleep 0.2)
    ;; Should have transitioned
    (is (eq :finished (current-state m)))))

(test timeout-cancelled-on-early-exit
  "Test timeout is cancelled when leaving state early"
  (let ((m (make-machine
            :states (list (list :name :waiting :timeout 0.5 :timeout-trigger :timeout)
                          :cancelled
                          :timed-out)
            :initial :waiting
            :transitions '((:trigger :cancel :source :waiting :dest :cancelled)
                           (:trigger :timeout :source :waiting :dest :timed-out)))))
    ;; Leave the state before timeout
    (fire m :cancel)
    (is (eq :cancelled (current-state m)))
    ;; Wait past the original timeout
    (sleep 0.6)
    ;; Should still be in cancelled state
    (is (eq :cancelled (current-state m)))))

(test cancel-timeout-function
  "Test cancel-timeout function"
  (let ((m (make-machine
            :states (list (list :name :waiting :timeout 0.5 :timeout-trigger :done)
                          :finished)
            :initial :waiting
            :transitions '((:trigger :done :source :waiting :dest :finished)))))
    ;; Manually cancel the timeout
    (cancel-timeout m)
    (sleep 0.6)
    ;; Should still be waiting
    (is (eq :waiting (current-state m)))))
