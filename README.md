# cl-transitions


A finite state machine library for Common Lisp with a clean, expressive API based off [pytransitions/transitions](https://github.com/pytransitions/transitions).

## Installation

```lisp
;; Clone into ~/quicklisp/local-projects/ then:
(ql:quickload :cl-transitions)
```

## Features

- **State machine definition** - Simple DSL for defining states and transitions
- **Callbacks** - `on-enter`, `on-exit`, `before`, `after`, `prepare`, `finalize`
- **Conditions** - Guard predicates to block transitions
- **Wildcards** - Use `:*` as source to match any state
- **Reflexive transitions** - Use `:=`, `:same`, or `:internal` as dest for internal transitions
- **Ordered transitions** - Priority ordering when multiple transitions match
- **Transition introspection** - Query available triggers and filter transitions
- **Auto-transitions** - Transitions that fire automatically on state entry
- **Finalize callbacks** - Always run after transition attempt (like try/finally)
- **Machine inheritance** - Compose and extend parent machines
- **Timeout transitions** - Auto-fire after specified duration in a state
- **Dynamic trigger methods** - Auto-generated trigger functions on model objects
- **State tags** - Group and query states by tags
- **Nested states** - States containing sub-machines for hierarchical FSM design
- **Queued mode** - Queue triggers fired during transitions to prevent re-entrancy

## Quick Start

```lisp
(use-package :cl-transitions)

;; Create a simple state machine
(defparameter *matter*
  (make-machine
   :states '(:solid :liquid :gas)
   :initial :solid
   :transitions '((:trigger :melt :source :solid :dest :liquid)
                  (:trigger :freeze :source :liquid :dest :solid)
                  (:trigger :boil :source :liquid :dest :gas)
                  (:trigger :condense :source :gas :dest :liquid))))

;; Fire transitions
(fire *matter* :melt)    ; => :liquid
(current-state *matter*) ; => :liquid
(fire *matter* :boil)    ; => :gas

;; Check if transition is possible
(may-fire-p *matter* :condense) ; => T
(may-fire-p *matter* :melt)     ; => NIL (not in :solid)
```

## Define-Machine Macro

For a more declarative syntax:

```lisp
(define-machine traffic-light
  (:states :red :yellow :green)
  (:initial :red)
  (:transitions
   (:to-green :red -> :green)
   (:to-yellow :green -> :yellow)
   (:to-red :yellow -> :red)))

;; Creates *traffic-light*
(fire *traffic-light* :to-green)
```

## Callbacks

All callbacks receive an `event-data` object with context:

```lisp
(let ((m (make-machine
          :states (list (list :name :a :on-exit (list (lambda (e)
                                                        (format t "Leaving ~A~%" (event-source e)))))
                        (list :name :b :on-enter (list (lambda (e)
                                                        (format t "Entering ~A~%" (event-dest e))))))
          :initial :a
          :transitions (list (list :trigger :go :source :a :dest :b
                                   :before (list (lambda (e)
                                                   (format t "Before transition~%")))
                                   :after (list (lambda (e)
                                                  (format t "After transition~%"))))))))
  (fire m :go))
;; Prints: Before transition
;;         Leaving A
;;         Entering B
;;         After transition
```

### Callback Order

1. `prepare` - Run before conditions are checked
2. `conditions` - Guard predicates (all must return T)
3. `before` - Run after conditions pass
4. `on-exit` - Run when leaving source state
5. State change happens
6. `on-enter` - Run when entering dest state
7. `after` - Run after state change
8. `finalize` - Always runs (even on failure)

## Conditions

Guard transitions with predicates:

```lisp
(let* ((temperature 20)
       (can-melt (lambda (e)
                   (declare (ignore e))
                   (> temperature 0)))
       (m (make-machine
           :states '(:solid :liquid)
           :initial :solid
           :transitions (list (list :trigger :melt :source :solid :dest :liquid
                                    :conditions (list can-melt))))))
  (fire m :melt)           ; => :liquid (temperature > 0)
  (setf temperature -10)
  (set-state m :solid)
  (fire m :melt)           ; => NIL (blocked by condition)
  (may-fire-p m :melt))    ; => NIL
```

## Priority / Ordered Transitions

When multiple transitions match the same trigger from the current state, they are evaluated in priority order (highest first). This is especially useful with conditions — you can define a generic fallback with low priority and specific matching rules with higher priority.

```lisp
(let* ((cond-val nil)
       (m (make-machine
           :states '(:a :b :c)
           :initial :a
           :transitions (list (list :trigger :go :source :a :dest :b
                                    :conditions (list (lambda (e)
                                                        (declare (ignore e))
                                                        cond-val))
                                    :priority 10)
                              (list :trigger :go :source :a :dest :c
                                    :priority 0)))))

  ;; Higher priority transition fails its condition, falls through to lower priority
  (fire m :go)           ; => :c
  (current-state m)      ; => :c

  ;; When condition passes, higher priority wins
  (setf cond-val t)
  (set-state m :a)
  (fire m :go)           ; => :b
  (current-state m)      ; => :b
```

```lisp
;; With define-machine macro
(define-machine task-manager
  (:states :idle :active :error)
  (:initial :idle)
  (:transitions
   (:start :idle -> :active)
   (:fail :active -> :error :priority 10)
   (:finish :active -> :idle :priority 0)))
```

Priority defaults to `0`. Higher numeric values are checked first. Transitions with equal priority maintain their relative order (stable sort).

```lisp
;; Via make-transition
(make-transition :go :a :b :priority 5)
```

## Transition Introspection

Query the machine to discover available triggers and transitions at runtime:

```lisp
(let ((m (make-machine
          :states '(:idle :processing :done)
          :initial :idle
          :transitions '((:trigger :start :source :idle :dest :processing)
                         (:trigger :finish :source :processing :dest :done)
                         (:trigger :reset :source :* :dest :idle)))))
  ;; Get all triggers available from current state
  (get-triggers m)              ; => (:start)

  ;; Get triggers from a specific state
  (get-triggers m :processing)  ; => (:finish :reset)

  ;; Find transitions matching criteria
  (find-transitions m :trigger :reset)              ; => all reset transitions
  (find-transitions m :source :processing)          ; => all transitions from processing
  (find-transitions m :dest :idle)                  ; => all transitions to idle
  (find-transitions m :trigger :start :source :idle) ; => specific transition
  (find-transitions m)                               ; => all transitions
```

- `get-triggers` checks structural source matching (including wildcards), not conditions
- `find-transitions` filters are ANDed — specify multiple to narrow the search
- With no filters, `find-transitions` returns every transition on the machine

## Reflexive Transitions

Internal transitions that don't trigger `on-exit`/`on-enter`:

```lisp
(make-machine
 :states '(:active)
 :initial :active
 :transitions '((:trigger :update :source :active :dest :=)))  ; or :same or :internal

;; Firing :update stays in :active but skips on-exit/on-enter
```

## Auto-Transitions

Transitions that fire automatically when entering their source state:

```lisp
(let ((m (make-machine
          :states '(:start :processing :done)
          :initial :start
          :transitions (list '(:trigger :begin :source :start :dest :processing)
                             (list :trigger :complete :source :processing :dest :done :auto t)))))
  (fire m :begin)
  (current-state m))  ; => :done (auto-transitioned from :processing)
```

Loop prevention is built-in via `:max-auto-transitions` (default 10).

## Finalize Callbacks

Run cleanup code regardless of success/failure:

```lisp
(let* ((cleaned-up nil)
       (m (make-machine
           :states '(:a :b)
           :initial :a
           :transitions (list (list :trigger :go :source :a :dest :b
                                    :conditions (list (constantly nil))  ; Always fails
                                    :finalize (list (lambda (e)
                                                      (setf cleaned-up t)
                                                      (format t "Success: ~A~%"
                                                              (event-transition-succeeded e)))))))))
  (fire m :go)    ; => NIL (condition failed)
  cleaned-up)     ; => T (finalize still ran)
```

## Machine Inheritance

Compose machines by inheriting from parent:

```lisp
(let* ((parent (make-machine
                :states '(:idle :working)
                :initial :idle
                :transitions '((:trigger :start :source :idle :dest :working))))
       (child (make-machine
               :states '(:done)  ; Add new state
               :initial :idle
               :transitions '((:trigger :finish :source :working :dest :done))
               :inherit-from parent)))
  ;; Child has all parent states/transitions plus its own
  (fire child :start)   ; => :working (inherited)
  (fire child :finish)) ; => :done (child's own)
```

## Dynamic Trigger Methods

When a machine is created with a `:model`, each trigger is automatically available as a function named by the trigger symbol, taking the model as the first argument:

```lisp
;; Define a model class
(defclass matter () ())

(let* ((model (make-instance 'matter))
       (machine (make-machine
                 :states '(:solid :liquid :gas)
                 :initial :solid
                 :model model
                 :transitions '((:trigger :melt :source :solid :dest :liquid)
                                (:trigger :boil :source :liquid :dest :gas)))))
  ;; Call triggers directly on the model
  (:melt model)        ; instead of (fire machine :melt)
  (current-state machine)  ; => :liquid
  (:boil model)
  (current-state machine)) ; => :gas
```

The machine is still accessible via `(model-machine model)`. Trigger functions support extra arguments which are passed through to transition callbacks.

```lisp
(model-machine model)  ; => the machine instance
```

> **Note:** Dynamic triggers use the same symbol as the trigger keyword (e.g., `:melt`). Calling a trigger on an unregistered model signals an `invalid-trigger-error`.

## State Tags

Group states with tags and query them at runtime:

```lisp
(let ((m (make-machine
          :states (list (list :name :solid  :tags '(:matter))
                        (list :name :liquid :tags '(:matter))
                        (list :name :gas    :tags '(:matter))
                        (list :name :start  :tags '(:control)))
          :initial :solid
          :transitions nil)))
  ;; Find all states tagged :matter
  (get-states-by-tag m :matter))  ; => list of state objects
  (mapcar #'state-name (get-states-by-tag m :matter))  ; => (:solid :liquid :gas)

  ;; Find states with :control tag
  (mapcar #'state-name (get-states-by-tag m :control))  ; => (:start)

  ;; Tags are inherited by child machines
```

- Use a plist state spec with `:tags` to tag states
- States defined as bare symbols have no tags
- `get-states-by-tag` returns state objects; use `state-name` to get the symbol

## Nested States

States can contain sub-machines for hierarchical FSM design. When entering a nested state, its sub-machine is automatically initialized. When exiting, the sub-machine is stopped.

```lisp
(let* ((sub (make-machine
             :states '(:idle :processing)
             :initial :idle
             :transitions '((:trigger :start-work :source :idle :dest :processing))))
       (machine (make-machine
                 :states (list (list :name :operating :submachine sub)
                               :stopped)
                 :initial :operating
                 :transitions '((:trigger :shutdown :source :operating :dest :stopped)))))
  ;; Sub-machine starts in :idle
  (current-state sub)  ; => :idle

  ;; Sub-machine processes its own events
  (fire sub :start-work)
  (current-state sub)  ; => :processing

  ;; Parent transitions out — sub-machine is stopped
  (fire machine :shutdown)
  (current-state machine)  ; => :stopped
)
```

Use `(state-submachine state)` to access the sub-machine from a state object. The sub-machine's callbacks and timeouts work independently.

> **Note:** The `:submachine` key is not supported in `define-machine`'s quoted syntax — use `make-machine` directly for nested states.

## Queued Mode

By default, triggers fired from within callbacks execute immediately (re-entrantly). This can cause unexpected state changes. Enable **queued mode** to defer triggers fired during transitions, processing them sequentially after the current transition completes.

```lisp
(let ((m (make-machine
          :states '(:a :b :c)
          :initial :a
          :queued t                     ; Enable queued mode
          :transitions (list
                        (list :trigger :go :source :a :dest :b
                              :after (list (lambda (e)
                                             ;; :next is queued, not executed yet
                                             (fire (event-machine e) :next))))
                        (list :trigger :next :source :b :dest :c)))))
  ;; Without queued: would end in :c (re-entrant :next fires immediately)
  ;; With queued: ends in :b (:next is queued, but state has already changed
  ;; to :b when :after runs — :next then fires from :b)
  (fire m :go))  ; => :b (not :c)
```

Queued mode ensures each transition runs to completion before the next starts. The queue is drained in FIFO order, and new triggers queued during drain are also processed.

```lisp
;; Access queue internals
(drain-queued-triggers m)          ; Manually drain pending queue
(machine-queued-p m)               ; Check if queued mode is enabled
(machine-processing-p m)           ; Check if currently processing
(machine-processing-queue m)       ; Inspect the pending queue
```

Queued mode requires no external dependencies — it uses a simple list and boolean flag.

## Timeout Transitions

States can auto-transition after a duration:

```lisp
(let ((m (make-machine
          :states (list (list :name :waiting
                              :timeout 5           ; 5 seconds
                              :timeout-trigger :timeout)
                        :timed-out)
          :initial :waiting
          :transitions '((:trigger :timeout :source :waiting :dest :timed-out)))))
  ;; After 5 seconds, :timeout fires automatically
  (sleep 6)
  (current-state m))  ; => :timed-out
```

Timeouts are cancelled when leaving the state early.

## API Reference

### Machine Functions

- `(make-machine &key states initial transitions model queued ...)` - Create a machine
- `(fire machine trigger &rest args)` - Fire a trigger
- `(may-fire-p machine trigger)` - Check if trigger can fire
- `(current-state machine)` - Get current state symbol
- `(set-state machine state-name)` - Directly set state
- `(add-state machine name &key on-enter on-exit tags submachine ...)` - Add a state
- `(add-transition machine transition)` - Add a transition
- `(get-state machine name)` - Get state object

### Queued Mode Functions

- `(machine-queued-p machine)` - Check if queued mode is enabled
- `(machine-processing-p machine)` - Check if a transition is currently being processed
- `(machine-processing-queue machine)` - Inspect the queue of pending triggers
- `(drain-queued-triggers machine)` - Manually drain all queued triggers

### Dynamic Trigger Functions

- `(model-machine model)` - Get the machine associated with a model
- `(collect-triggers machine)` - List all unique trigger symbols
- `(add-dynamic-triggers machine)` - Set up trigger functions for the machine's model

### Introspection Functions

- `(get-triggers machine &optional state)` - List trigger symbols available from state (defaults to current)
- `(find-transitions machine &key trigger source dest)` - Find transitions matching optional filters
- `(get-states-by-tag machine tag)` - Find all state objects with a given tag symbol

### Inheritance Functions

- `(copy-state state)` - Deep copy a state
- `(copy-transition transition)` - Deep copy a transition
- `(inherit-machine child parent &key override)` - Inherit states/transitions

### Timeout Functions

- `(cancel-timeout machine)` - Cancel pending timeout
- `(start-timeout machine state-name duration trigger)` - Start timeout

### Transition Functions

- `(make-transition trigger source dest &key before after prepare conditions finalize auto priority)` - Create a transition
- `(transition-priority transition)` - Get the priority of a transition
- `(reflexive-dest-p dest)` - Check if dest is reflexive
- `(resolve-transition-dest transition current)` - Resolve actual destination

## Running Tests

```lisp
(ql:quickload :cl-transitions/tests)
(cl-transitions/tests:run-tests)
```

## TODO

- [x] Auto-transitions - Transitions that fire automatically when entering a state
- [x] Reflexive transitions - dest: '=' to stay in same state (internal transitions)
- [x] Queued/Async mode - Queue triggers during transition execution, process sequentially
- [x] Hierarchical/Nested FSM - States containing sub-machines (NestedState)
- [x] State tags - Grouping states with tags for querying
- [x] Dynamic trigger methods - Auto-generated trigger functions on model objects
- [x] Transition reflection - get_transitions(), get_triggers() introspection
- [ ] Graphviz export - Generate state diagrams
- [x] Finalize callbacks - Always run after transition (even on failure)
- [x] State machine inheritance - Extending/composing machines
- [x] Ordered transitions - Priority when multiple transitions match
- [x] Timeout transitions - Auto-fire after duration

## License

[GPLv3](https://www.gnu.org/licenses/gpl-3.0.en.html)
