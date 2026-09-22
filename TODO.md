# Nim Port TODO

This document outlines the features needed for a faithful Nim port of
[pytransitions/transitions](https://github.com/pytransitions/transitions) (v0.9.4).
Items are ordered by importance (Tier 1 = must-have, Tier 4 = nice-to-have).

---

## Tier 1 — Core FSM

- [ ] **Machine type** — manage states, transitions, and models.
  - Constructor params: `model`, `states`, `initial`, `transitions`, `send_event`,
    `auto_transitions`, `ignore_invalid_triggers`, `queued`, `model_attribute`,
    `model_override`, `before_state_change`, `after_state_change`, `prepare_event`,
    `finalize_event`, `on_exception`, `on_final`, `name`.
  - Support standalone mode (no external model), model injection, and multi-model.
- [ ] **State type** — fields: `name`, `on_enter`, `on_exit`, `final`,
  `ignore_invalid_triggers`. Support `add_callback(trigger, func)`.
- [ ] **Transition type** — fields: `source`, `dest`, `prepare`, `conditions`,
  `before`, `after`. Support `add_callback(trigger, func)`. Internal transitions
  (dest = nil).
- [ ] **Event type** — maps source states to transitions. `trigger(model, args)`
  iterates transitions, picks first match.
- [ ] **EventData type** — carries `state`, `event`, `machine`, `model`, `args`,
  `kwargs`, `transition`, `error`.
- [ ] **Condition type** — wraps a predicate with a target bool. AND logic for
  conditions, inverted for `unless`.
- [ ] **Trigger injection** — dynamically add `trigger_name(args)` procs to model.
  - `to_<state>()` auto-transitions (unless `auto_transitions=false`).
  - `is_<state>()` state checks.
  - `may_<trigger>()` / `may_trigger(name)` guard checks.
  - `trigger(name, args)` generic dispatch.
  - `get_triggers(state)` query.
- [ ] **Callback resolution** — resolve callbacks by name (model method, property,
  module path with dots) or by direct proc reference.
- [ ] **Execution order** — implement the full ordered pipeline:
  1. `prepare_event` (global)
  2. `transition.prepare`
  3. evaluate `conditions` / `unless`
  4. `before_state_change` (global)
  5. `transition.before`
  6. `state.on_exit` (source)
  7. state attribute update
  8. `state.on_enter` (dest)
  9. `on_final` if dest is final
  10. `transition.after`
  11. `after_state_change` (global)
  12. `finalize_event` (always, even on error)
  - Error handling: if machine has `on_exception`, call it and swallow error;
    otherwise re-raise. `finalize_event` always runs.
- [ ] **Wildcard source** (`'*'`) — match any state.
- [ ] **Reflexive dest** (`'='`) — destination equals source.
- [ ] **Multiple source states** — list of sources per trigger.
- [ ] **Queued transitions** — defer triggers fired inside callbacks; process
    serial. `queued=true`.
- [ ] **MachineError** — custom exception for invalid transitions, missing states.
- [ ] **`add_transition(trigger, source, dest, opts)`** and
    **`add_transitions(list)`** — accept dict-style or list-style configs.
- [ ] **`dispatch(trigger, args)`** — trigger an event on all models at once.
- [ ] **`add_model(model, initial)` / `remove_model(model)`** — dynamic model
    lifecycle management.
- [ ] **`get_state(name)`** / `set_state(name)` — direct state manipulation.

---

## Tier 2 — Standard Features

- [ ] **Enum states** — support Nim `enum` as state identifiers. Map to strings
    internally via `$enum`.
- [ ] **Custom `model_attribute`** — configurable attribute name on model for
    storing current state. Affects `is_<attr>_<state>()` / `to_<attr>_<state>()`.
- [ ] **Ordered transitions** — `add_ordered_transitions(sequence, conditions, loop)`
    for linear state sequences.
- [ ] **`send_event=true` mode** — pass `EventData` instead of raw args.
- [ ] **Internal transitions** — `dest=nil`, no exit/enter callbacks.
- [ ] **`on_enter_<state>()` / `on_exit_<state>()`** dynamic callback attachment
    via `__getattr__`-style metaprog (Nim: `methodMissing` or macro dispatch).
- [ ] **`before_<trigger>()` / `after_<trigger>()`** dynamic callback attachment.
- [ ] **Multi-model** — single machine managing N independent model instances.
- [ ] **Logging** — structured logging via Nim `logging` module with machine name
    prefix.
- [ ] **`ignore_invalid_triggers`** — per-state and global.
- [ ] **Property/attribute conditions** — non-callable model fields used as
    conditions (nil-safe, wrapped).

---

## Tier 3 — Extensions

### Hierarchical (Nested) State Machine

- [ ] **NestedState** — states with child states, initial child, parallel flag.
- [ ] **NestedTransition** — handle enter/exit of nested state trees (walk up/down).
- [ ] **NestedEvent** — breadth-first trigger search through hierarchy.
- [ ] **HierarchicalMachine** — `get_state(path)` with separator (`_` or `.`),
    `to_state(model, path)`, context-manager scope for adding children.
- [ ] **Parallel states** — multiple active substates concurrently.
- [ ] **Final state detection** — walk hierarchy to determine completeness.

### Diagram Generation

- [ ] **GraphMachine** — `get_graph(title)` returning a graph object with `draw()`.
- [ ] **Graph backends** — support at least one backend (Graphviz via CLI or
    a Nim-native graph library like `graphviz`).
- [ ] **Mermaid output** — generate Mermaid diagram string.
- [ ] **Styling** — configurable node/edge/graph attributes.
- [ ] **Active state highlighting** — `TransitionGraphSupport` update on execute.
- [ ] **Region of Interest** — `show_roi=true` filters to reachable states.

### Thread Safety

- [ ] **LockedMachine** — thread-safe wrapper using Nim `locks` or `channels`.
    Per-model context locking.

### Async Support

- [ ] **AsyncMachine** — async variant using Nim `async/await`.
    Async callbacks, async condition checks.
- [ ] **AsyncTimeout** — timeout state using async sleep (no threads).
- [ ] **Per-model async queue** — `queued='model'` for independent per-model
    queues.

### State Features (Mixins)

- [ ] **Tags mixin** — `.tags` on state, `state.is_<tag>()` queries.
- [ ] **Error state** — raises if no outgoing transition and `accepted` not tagged.
- [ ] **Timeout state** — `timeout` (seconds), `on_timeout` callback.
- [ ] **Volatile state** — create/fresh object on enter, assign to model scope.
- [ ] **Retry state** — limit re-entries from same source; `retries=N`,
    `on_failure=callback`.
- [ ] **`add_state_features`** — composable mixin system for custom state types.

### Serialization / Markup

- [ ] **MarkupMachine** — serialize full machine config (states, transitions,
    callbacks) to a JSON-compatible struct.
- [ ] **Reconstruct from markup** — build machine from serialized config.
- [ ] **HierarchicalMarkupMachine** — HSM + markup.

---

## Tier 4 — Polish & DX

- [ ] **Inheritance-friendly factory methods** — `create_state()`,
    `create_transition()`, `create_event()`, `create_condition()` overridable so
    users can subclass and customise.
- [ ] **`get_triggers(*states)`** — query available triggers from one or more states.
- [ ] **`get_transitions(trigger, source, dest)`** — query matching transitions.
- [ ] **`remove_transition(trigger, source, dest)`** — remove a specific transition.
- [ ] **`transition(source, dest, ...) helper** — returns a transition config
    dict/object for better typing (from experimental utils).
- [ ] **`with_model_definitions` equivalent** — descriptor-based trigger
    definitions directly on model type body (macro support).
- [ ] **`generate_base_model` equivalent** — generate a model type definition
    with all triggers as methods (macro).
- [ ] **`MachineFactory`** — convenience factory for composing machine features:
    - Machine, LockedMachine, HierarchicalMachine, GraphMachine,
      LockedHierarchicalMachine, LockedGraphMachine, HierarchicalGraphMachine,
      LockedHierarchicalGraphMachine, AsyncMachine, AsyncGraphMachine,
      HierarchicalAsyncMachine, HierarchicalAsyncGraphMachine.
- [ ] **Pickling / serialization** — `save`/`load` machine state (JSON, YAML,
    or Nim `marshal`).
- [ ] **Comprehensive test suite** — port the Python test suite (tests/ directory).
- [ ] **Nimble package** — `transitions.nimble` with proper metadata, CI, docs.
- [ ] **Examples** — port the examples/ directory (especially the NarcolepticSuperhero
    quickstart).
- [ ] **Type stubs / API docs** — documented public API.
