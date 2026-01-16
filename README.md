# cl-transitions

## TODO

1. Auto-transitions - Transitions that fire automatically when entering a state (e.g., dest: '=next' syntax)
2. Reflexive transitions - dest: '=' to stay in same state (internal transitions)
3. Queued/Async mode - Queue triggers during transition execution, process sequentially
4. Hierarchical/Nested FSM - States containing sub-machines (NestedState)
5. State tags - Grouping states with tags for querying (machine.get_states(tag='active'))
6. Dynamic trigger methods - Auto-generated methods on model (e.g., model.melt() instead of fire(m, :melt))
7. Transition reflection - get_transitions(), get_triggers() introspection
8. Graphviz export - Generate state diagrams
9. Finalize callbacks - Always run after transition (even on failure)
10. State machine inheritance - Extending/composing machines
11. Ordered transitions - Priority when multiple transitions match
12. Timeout transitions - Auto-fire after duration

## License

GPLv3
