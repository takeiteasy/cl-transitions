# cl-transitions

Common Lisp port of [pytransitions/transitions](https://github.com/pytransitions/transitions)

A finite state machine library for Common Lisp with a clean, expressive API.

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
- **Auto-transitions** - Transitions that fire automatically on state entry
- **Finalize callbacks** - Always run after transition attempt (like try/finally)
- **Machine inheritance** - Compose and extend parent machines
- **Timeout transitions** - Auto-fire after specified duration in a state

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

- `(make-machine &key states initial transitions model ...)` - Create a machine
- `(fire machine trigger &rest args)` - Fire a trigger
- `(may-fire-p machine trigger)` - Check if trigger can fire
- `(current-state machine)` - Get current state symbol
- `(set-state machine state-name)` - Directly set state
- `(add-state machine name &key on-enter on-exit ...)` - Add a state
- `(add-transition machine transition)` - Add a transition
- `(get-state machine name)` - Get state object

### Inheritance Functions

- `(copy-state state)` - Deep copy a state
- `(copy-transition transition)` - Deep copy a transition
- `(inherit-machine child parent &key override)` - Inherit states/transitions

### Timeout Functions

- `(cancel-timeout machine)` - Cancel pending timeout
- `(start-timeout machine state-name duration trigger)` - Start timeout

### Utility Functions

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
- [ ] Queued/Async mode - Queue triggers during transition execution, process sequentially
- [ ] Hierarchical/Nested FSM - States containing sub-machines (NestedState)
- [ ] State tags - Grouping states with tags for querying
- [ ] Dynamic trigger methods - Auto-generated methods on model
- [ ] Transition reflection - get_transitions(), get_triggers() introspection
- [ ] Graphviz export - Generate state diagrams
- [x] Finalize callbacks - Always run after transition (even on failure)
- [x] State machine inheritance - Extending/composing machines
- [ ] Ordered transitions - Priority when multiple transitions match
- [x] Timeout transitions - Auto-fire after duration

## License

GPLv3
