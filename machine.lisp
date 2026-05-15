;;;; machine.lisp - Machine class for cl-transitions

(in-package #:cl-transitions)

(defclass machine ()
  ((model :initarg :model
          :accessor machine-model
          :initform nil
          :documentation "Optional external model object")
   (states :initarg :states
           :accessor machine-states
           :initform (make-hash-table)
           :documentation "Hash table mapping state names to state objects")
   (transitions :initarg :transitions
                :accessor machine-transitions
                :initform nil
                :type list
                :documentation "List of transition objects")
   (current-state :initarg :current-state
                  :accessor machine-current-state
                  :type symbol
                  :documentation "The current state of the machine")
   (initial-state :initarg :initial-state
                  :accessor machine-initial-state
                  :type symbol
                  :documentation "The initial state of the machine")
   (auto-transitions :initarg :auto-transitions
                     :accessor machine-auto-transitions
                     :initform t
                     :type boolean
                     :documentation "Whether to automatically execute transitions")
   (ignore-invalid-triggers :initarg :ignore-invalid-triggers
                            :accessor machine-ignore-invalid-triggers
                            :initform nil
                            :type boolean
                            :documentation "If T, invalid triggers return NIL instead of signaling an error")
   (auto-transition-depth :initarg :auto-transition-depth
                          :accessor machine-auto-transition-depth
                          :initform 0
                          :type integer
                          :documentation "Current depth of auto-transition chain")
   (max-auto-transitions :initarg :max-auto-transitions
                         :accessor machine-max-auto-transitions
                         :initform 10
                         :type integer
                         :documentation "Maximum allowed auto-transition chain depth")
   (timeout-thread :initarg :timeout-thread
                   :accessor machine-timeout-thread
                   :initform nil
                   :documentation "Current timeout thread, or NIL if no timeout active")
   (timeout-lock :initarg :timeout-lock
                 :accessor machine-timeout-lock
                 :initform (bt:make-lock "timeout-lock")
                 :documentation "Lock for thread-safe timeout operations")
    (timeout-cancelled :initarg :timeout-cancelled
                       :accessor machine-timeout-cancelled
                       :initform nil
                       :type boolean
                       :documentation "Flag to signal timeout thread should abort")
   (queued :initarg :queued
           :accessor machine-queued-p
           :initform nil
           :type boolean
           :documentation "If T, triggers fired during transition processing are queued and processed sequentially after the current transition completes")
   (processing-p :initarg :processing-p
                 :accessor machine-processing-p
                 :initform nil
                 :type boolean
                 :documentation "If T, a transition is currently being processed")
   (processing-queue :initarg :processing-queue
                     :accessor machine-processing-queue
                     :initform nil
                     :type list
                     :documentation "Queue of pending (trigger . args) for queued mode"))
  (:documentation "The finite state machine controller"))

(defmethod print-object ((machine machine) stream)
  (print-unreadable-object (machine stream :type t :identity t)
    (format stream "state: ~S" (machine-current-state machine))))

(defun add-state (machine state-or-name &key on-enter on-exit timeout timeout-trigger
                            tags submachine)
  "Add a state to the machine.
STATE-OR-NAME can be a state object or a symbol (state name).
TAGS is a list of tag symbols for grouping and querying states.
SUBMACHINE is an optional machine instance for nested/hierarchical states.
Returns the state object."
  (let ((state (etypecase state-or-name
                 (state state-or-name)
                 (symbol (make-state state-or-name
                                     :on-enter on-enter
                                     :on-exit on-exit
                                     :timeout timeout
                                     :timeout-trigger timeout-trigger
                                     :tags tags
                                     :submachine submachine)))))
    (setf (gethash (state-name state) (machine-states machine)) state)
    state))

(defun add-transition (machine transition)
  "Add a transition to the machine. Returns the transition."
  (push transition (machine-transitions machine))
  transition)

(defun get-state (machine state-name)
  "Get the state object for STATE-NAME, or NIL if not found."
  (gethash state-name (machine-states machine)))

(defun current-state (machine)
  "Get the current state symbol of the machine."
  (machine-current-state machine))

(defun set-state (machine state-name)
  "Set the current state of the machine to STATE-NAME.
Signals INVALID-STATE-ERROR if the state doesn't exist.
Returns the new state name."
  (unless (get-state machine state-name)
    (error 'invalid-state-error
           :machine machine
           :state state-name
           :message (format nil "State ~A does not exist" state-name)))
  (setf (machine-current-state machine) state-name))

(defun find-transitions-for-trigger (machine trigger)
  "Find all transitions matching TRIGGER from the current state.
Returns a list of matching transition objects, sorted by priority
(highest first). Transitions with equal priority preserve their
relative order (stable sort)."
  (let ((current (machine-current-state machine)))
    (stable-sort (remove-if-not (lambda (trans)
                                  (and (eq (transition-trigger trans) trigger)
                                       (transition-matches-source-p trans current)))
                                (machine-transitions machine))
                 #'>
                 :key #'transition-priority)))

(defun find-transitions (machine &key trigger source dest)
  "Find transitions matching optional filters. All filters are ANDed.
TRIGGER filters by trigger symbol.
SOURCE filters by source state (supports wildcard/:* matching).
DEST filters by destination state.
Returns a list of matching transition objects."
  (remove-if-not (lambda (trans)
                   (and (or (null trigger) (eq (transition-trigger trans) trigger))
                        (or (null source) (transition-matches-source-p trans source))
                        (or (null dest) (eq (transition-dest trans) dest))))
                 (machine-transitions machine)))

(defun get-triggers (machine &optional state)
  "Get all trigger symbols available from STATE (defaults to current state).
A trigger is available if there is at least one transition with that
trigger whose source matches the given state. Conditions are not checked.
Returns a list of unique trigger symbols."
  (let ((state (or state (machine-current-state machine))))
    (delete-duplicates
     (mapcar #'transition-trigger
             (remove-if-not (lambda (trans)
                              (transition-matches-source-p trans state))
                            (machine-transitions machine))))))

(defun get-states-by-tag (machine tag)
  "Find all states in MACHINE that have the given TAG.
TAG is a symbol used for grouping states.
Returns a list of state objects (not just names)."
  (let ((result nil))
    (maphash (lambda (name state)
               (declare (ignore name))
               (when (member tag (state-tags state))
                 (push state result)))
             (machine-states machine))
    (nreverse result)))

;;; ---------------------------------------------------------------------------
;;; Machine Inheritance
;;; ---------------------------------------------------------------------------

(defun copy-state (state)
  "Create a deep copy of STATE.
Callbacks are copied by reference (they are assumed to be functions).
The submachine is copied by reference (not deep-copied)."
  (make-instance 'state
                 :name (state-name state)
                 :tags (copy-list (state-tags state))
                 :submachine (state-submachine state)
                 :on-enter (copy-list (state-on-enter state))
                 :on-exit (copy-list (state-on-exit state))
                 :timeout (state-timeout state)
                 :timeout-trigger (state-timeout-trigger state)))

(defun copy-transition (trans)
  "Create a deep copy of TRANS.
Callbacks and conditions are copied by reference."
  (make-instance 'transition
                 :trigger (transition-trigger trans)
                 :source (let ((src (transition-source trans)))
                           (if (listp src) (copy-list src) src))
                 :dest (transition-dest trans)
                 :before (copy-list (transition-before trans))
                 :after (copy-list (transition-after trans))
                 :prepare (copy-list (transition-prepare trans))
                  :conditions (copy-list (transition-conditions trans))
                  :finalize (copy-list (transition-finalize trans))
                  :auto (transition-auto-p trans)
                  :priority (transition-priority trans)))

(defun inherit-states (child parent &key (override t))
  "Copy states from PARENT machine to CHILD machine.
If OVERRIDE is T (default), child definitions take precedence.
If OVERRIDE is NIL, parent definitions take precedence.
Returns the child machine."
  (maphash (lambda (name state)
             (let ((existing (get-state child name)))
               (when (or (not existing)
                         (not override))
                 (setf (gethash name (machine-states child))
                       (copy-state state)))))
           (machine-states parent))
  child)

(defun inherit-transitions (child parent &key (override t))
  "Copy transitions from PARENT machine to CHILD machine.
If OVERRIDE is T (default), child definitions take precedence.
If OVERRIDE is NIL, parent definitions take precedence (duplicates allowed).
Returns the child machine."
  (let ((parent-transitions (mapcar #'copy-transition (machine-transitions parent))))
    (if override
        ;; Add parent transitions that don't conflict with child
        (dolist (ptrans parent-transitions)
          (let ((exists (find-if (lambda (ctrans)
                                   (and (eq (transition-trigger ptrans)
                                            (transition-trigger ctrans))
                                        (equal (transition-source ptrans)
                                               (transition-source ctrans))))
                                 (machine-transitions child))))
            (unless exists
              (push ptrans (machine-transitions child)))))
        ;; Add all parent transitions (parent wins, add first)
        (setf (machine-transitions child)
              (append parent-transitions (machine-transitions child)))))
  child)

(defun inherit-machine (child parent &key (override t))
  "Inherit both states and transitions from PARENT to CHILD.
If OVERRIDE is T (default), child definitions take precedence.
If OVERRIDE is NIL, parent definitions take precedence.
Returns the child machine."
  (inherit-states child parent :override override)
  (inherit-transitions child parent :override override)
  child)
