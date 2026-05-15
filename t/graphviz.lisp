;;;; t/graphviz.lisp - Graphviz export examples and tests

(in-package #:cl-transitions)

(defun gv-examples-dir ()
  "Return the output directory for graphviz examples."
  (uiop:ensure-pathname
   (merge-pathnames #p"graphviz-examples/"
                    (asdf:system-source-directory :cl-transitions))))

(defun ensure-gv-examples-dir ()
  (ensure-directories-exist (gv-examples-dir)))

;;; ---------------------------------------------------------------------------
;;; 1. Traffic Light — timer-based cycle with conditional transitions
;;; ---------------------------------------------------------------------------

(defun make-traffic-light ()
  (let* ((timer 0)
         (green-time 30)
         (yellow-time 5)
         (red-time 25)
         (green-expired (lambda (e) (declare (ignore e)) (>= timer green-time)))
         (yellow-expired (lambda (e) (declare (ignore e)) (>= timer (+ green-time yellow-time))))
         (red-expired (lambda (e) (declare (ignore e)) (>= timer (+ green-time yellow-time red-time)))))
    (make-machine
     :states '(:green :yellow :red)
     :initial :green
     :transitions
     (list (list :trigger :tick :source :green :dest :yellow
                 :conditions (list green-expired))
           (list :trigger :tick :source :yellow :dest :red
                 :conditions (list yellow-expired))
           (list :trigger :tick :source :red :dest :green
                 :conditions (list red-expired))))))

;;; ---------------------------------------------------------------------------
;;; 2. Matter — multi-path with wildcard reset
;;; ---------------------------------------------------------------------------

(defun make-matter-machine ()
  (make-machine
   :states '(:solid :liquid :gas :plasma)
   :initial :solid
   :transitions '((:trigger :melt :source :solid :dest :liquid)
                  (:trigger :freeze :source :liquid :dest :solid)
                  (:trigger :boil :source :liquid :dest :gas)
                  (:trigger :condense :source :gas :dest :liquid)
                  (:trigger :sublimate :source :solid :dest :gas)
                  (:trigger :deposit :source :gas :dest :solid)
                  (:trigger :ionize :source :gas :dest :plasma)
                  (:trigger :deionize :source :plasma :dest :gas)
                  (:trigger :reset :source :* :dest :solid))))

;;; ---------------------------------------------------------------------------
;;; 3. Document Workflow — complex with auto, reflexive, conditions
;;; ---------------------------------------------------------------------------

(defun make-document-workflow ()
  (make-machine
   :states (list :draft
                 :review
                 (list :name :approved :tags '(:terminal))
                 (list :name :rejected :tags '(:terminal))
                 :archived)
   :initial :draft
   :transitions (list
                 ;; Submit for review
                 (list :trigger :submit :source :draft :dest :review)
                 ;; Auto-archive approved documents
                 (list :trigger :auto-archive :source :approved :dest :archived
                       :auto t)
                 ;; Approve
                 (list :trigger :approve :source :review :dest :approved)
                 ;; Reject — goes back to draft
                 (list :trigger :reject :source :review :dest :draft)
                 ;; Update while in draft (reflexive)
                 (list :trigger :update :source :draft :dest :same)
                 ;; Resubmit from rejected
                 (list :trigger :resubmit :source :rejected :dest :review)
                 ;; Recall from review back to draft
                 (list :trigger :recall :source :review :dest :draft)
                 ;; Archive from any terminal state
                  (list :trigger :archive :source '(:approved :rejected) :dest :archived))))

;;; ---------------------------------------------------------------------------
;;; 4. Turnstile — classic simple FSM
;;; ---------------------------------------------------------------------------

(defun make-turnstile ()
  (make-machine
   :states '(:locked :unlocked)
   :initial :locked
   :transitions '((:trigger :coin :source :locked :dest :unlocked)
                  (:trigger :push :source :unlocked :dest :locked))))

;;; ---------------------------------------------------------------------------
;;; 5. Vending Machine — multiple items, change, service mode
;;; ---------------------------------------------------------------------------

(defun make-vending-machine ()
  (let* ((inserted 0)
         (dispensed nil)
         (change-log nil)
         (has-money (lambda (e) (declare (ignore e)) (> inserted 0)))
         (enough-for-soda (lambda (e) (declare (ignore e)) (>= inserted 150)))
         (enough-for-snack (lambda (e) (declare (ignore e)) (>= inserted 100)))
         (enough-for-water (lambda (e) (declare (ignore e)) (>= inserted 75)))
         (dispense-fn (lambda (item)
                        (lambda (e) (declare (ignore e)) (push item dispensed))))
         (give-change-fn (lambda (e)
                           (declare (ignore e))
                           (when (> inserted 0)
                             (push inserted change-log)
                             (setf inserted 0)))))
    (make-machine
     :states (list :idle
                   :has-credit
                   :dispensing
                   (list :name :out-of-order :tags '(:service)))
     :initial :idle
     :transitions
     (list
      ;; Insert coins
      (list :trigger :insert-coin :source :idle :dest :has-credit
            :after (list (lambda (e)
                           (declare (ignore e))
                           (incf inserted 25))))
      (list :trigger :insert-coin :source :has-credit :dest :has-credit
            :after (list (lambda (e)
                           (declare (ignore e))
                           (incf inserted 25))))
      ;; Select items
      (list :trigger :select-soda :source :has-credit :dest :dispensing
            :conditions (list enough-for-soda)
             :before (list (funcall dispense-fn :soda))
            :after (list give-change-fn))
      (list :trigger :select-snack :source :has-credit :dest :dispensing
            :conditions (list enough-for-snack)
             :before (list (funcall dispense-fn :snack))
            :after (list give-change-fn))
      (list :trigger :select-water :source :has-credit :dest :dispensing
            :conditions (list enough-for-water)
             :before (list (funcall dispense-fn :water))
            :after (list give-change-fn))
      ;; Finish dispensing (auto-transition back to idle)
      (list :trigger :finish :source :dispensing :dest :idle :auto t)
      ;; Cancel — return coins
      (list :trigger :cancel :source :has-credit :dest :idle
            :after (list give-change-fn))
      ;; Service mode
      (list :trigger :enter-service :source :* :dest :out-of-order)
      (list :trigger :exit-service :source :out-of-order :dest :idle)))))

;;; ---------------------------------------------------------------------------
;;; 6. Priority-based elevator controller
;;; ---------------------------------------------------------------------------

(defun make-elevator ()
  (make-machine
   :states '(:idle :moving-up :moving-down :door-open :obstructed :emergency)
   :initial :idle
   :transitions (list
                 ;; Normal operation
                 (list :trigger :call-floor :source :idle :dest :moving-up)
                 (list :trigger :arrived :source :moving-up :dest :door-open)
                 (list :trigger :arrived :source :moving-down :dest :door-open)
                 (list :trigger :close-door :source :door-open :dest :idle)
                 ;; Direction change (must stop first)
                 (list :trigger :stop :source :moving-up :dest :idle)
                 (list :trigger :stop :source :moving-down :dest :idle)
                 (list :trigger :go-up :source :idle :dest :moving-up)
                 (list :trigger :go-down :source :idle :dest :moving-down)
                 ;; Door obstruction (reflexive)
                 (list :trigger :obstruct :source :door-open :dest :obstructed)
                 (list :trigger :clear :source :obstructed :dest :door-open)
                 ;; Emergency — from any state
                 (list :trigger :emergency :source :* :dest :emergency)
                 (list :trigger :reset :source :emergency :dest :idle))))

;;; ---------------------------------------------------------------------------
;;; 7. Traffic light with current state changed (tests highlighting)
;;; ---------------------------------------------------------------------------

(defun make-traffic-light-at-red ()
  (let ((m (make-traffic-light)))
    (fire m :tick)
    (fire m :tick)
    (fire m :tick)
    m))

;;; ---------------------------------------------------------------------------
;;; 8. Nested submachine:  Phone call
;;; ---------------------------------------------------------------------------

(defun make-phone-machine ()
  (let ((call-sub (make-machine
                   :states '(:dialing :ringing :connected :call-ended)
                   :initial :dialing
                   :transitions '((:trigger :connect :source :dialing :dest :ringing)
                                  (:trigger :answer :source :ringing :dest :connected)
                                  (:trigger :hang-up :source :connected :dest :call-ended)
                                  (:trigger :timeout :source :dialing :dest :call-ended)
                                  (:trigger :cancel :source :ringing :dest :call-ended)))))
    (make-machine
     :states (list :off
                   (list :name :active :submachine call-sub))
     :initial :off
     :transitions '((:trigger :power-on :source :off :dest :active)
                    (:trigger :power-off :source :active :dest :off)))))

;;; ---------------------------------------------------------------------------
;;; Generate all examples
;;; ---------------------------------------------------------------------------

(defun generate-all-graphviz-examples ()
  "Generate DOT files for all example state machines."
  (ensure-gv-examples-dir)
  (let ((examples (list
                    (list "traffic-light" (make-traffic-light))
                    (list "traffic-light-at-red" (make-traffic-light-at-red))
                    (list "matter" (make-matter-machine))
                    (list "document-workflow" (make-document-workflow))
                    (list "turnstile" (make-turnstile))
                    (list "vending-machine" (make-vending-machine))
                    (list "elevator" (make-elevator))
                    (list "phone-machine" (make-phone-machine))))
        (dir (gv-examples-dir)))
    (dolist (example examples)
      (destructuring-bind (name machine) example
        (let ((dot-path (merge-pathnames (format nil "~A.dot" name) dir)))
          (cl-transitions/graphviz:write-dot machine dot-path)
          (format t "Wrote ~A~%" dot-path)))))
  (values))

;;; ---------------------------------------------------------------------------
;;; Programmatic verification: check DOT output structure
;;; ---------------------------------------------------------------------------

(defun dot-has-node-p (dot-string node-name)
  "Check if DOT output contains a node with the given name."
  (search (format nil "\"~A\"" (string node-name)) dot-string :test #'char-equal))

(defun dot-has-edge-p (dot-string from to)
  "Check if DOT output contains an edge from FROM to TO."
  (let ((pattern (format nil "\"~A\" -> \"~A\"" (string from) (string to))))
    (search pattern dot-string :test #'char-equal)))

(defun verify-graphviz-examples ()
  "Verify the DOT output of example machines programmatically."
  (let ((results nil))
    ;; 1. Turnstile: 2 states, 2 transitions
    (let ((dot (cl-transitions/graphviz:machine->dot (make-turnstile))))
      (push (list :turnstile-states (and (dot-has-node-p dot :locked)
                                          (dot-has-node-p dot :unlocked))) results)
      (push (list :turnstile-edges (and (dot-has-edge-p dot :locked :unlocked)
                                         (dot-has-edge-p dot :unlocked :locked))) results))
    ;; 2. Traffic light initial state
    (let ((dot (cl-transitions/graphviz:machine->dot (make-traffic-light))))
      (push (list :traffic-light-initial (dot-has-node-p dot :green)) results))
    ;; 3. Traffic light at red: initial green, current red
    (let ((dot (cl-transitions/graphviz:machine->dot (make-traffic-light-at-red))))
      (push (list :traffic-light-red-current (dot-has-node-p dot :red)) results))
    ;; 4. Matter wildcard
    (let ((dot (cl-transitions/graphviz:machine->dot (make-matter-machine))))
      (push (list :matter-all-states (and (dot-has-node-p dot :solid)
                                           (dot-has-node-p dot :liquid)
                                           (dot-has-node-p dot :gas)
                                           (dot-has-node-p dot :plasma))) results)
      ;; Wildcard :* should create edges from ALL states to :solid for reset
      (push (list :matter-wildcard-reset (and (dot-has-edge-p dot :liquid :solid)
                                               (dot-has-edge-p dot :gas :solid)
                                               (dot-has-edge-p dot :plasma :solid))) results))
    ;; 5. Document workflow: reflexive, auto, list-source
    (let ((dot (cl-transitions/graphviz:machine->dot (make-document-workflow))))
      (push (list :doc-reflexive (dot-has-edge-p dot :draft :draft)) results)
      ;; auto-archive should be dashed
      (push (list :doc-auto-archive (and (dot-has-edge-p dot :approved :archived)
                                          (search "dashed" dot :test #'char-equal))) results))
    ;; 6. Vending machine
    (let ((dot (cl-transitions/graphviz:machine->dot (make-vending-machine))))
      (push (list :vending-all-states (and (dot-has-node-p dot :idle)
                                            (dot-has-node-p dot :has-credit)
                                            (dot-has-node-p dot :dispensing)
                                            (dot-has-node-p dot :out-of-order))) results))
    ;; 7. Elevator
    (let ((dot (cl-transitions/graphviz:machine->dot (make-elevator))))
      (push (list :elevator-emergency-wildcard (and (dot-has-edge-p dot :idle :emergency)
                                                     (dot-has-edge-p dot :door-open :emergency)
                                                     (dot-has-edge-p dot :obstructed :emergency))) results))
    ;; Report
    (format t "~&Graphviz verification results:~%")
    (dolist (r (nreverse results))
      (destructuring-bind (test result) r
        (format t "  ~30A ~A~%" test (if result "PASS" "FAIL"))))
    (let ((all-pass (every #'second results)))
      (if all-pass
          (format t "~&All graphviz tests PASS.~%")
          (format t "~&Some graphviz tests FAIL.~%"))
      all-pass)))
