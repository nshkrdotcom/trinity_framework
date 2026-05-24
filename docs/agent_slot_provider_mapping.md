# Agent Slot Provider Mapping

`trinity_framework` separates route selection from provider dispatch. Router
outputs identify an agent slot and role; provider bridges decide how that slot
maps to a concrete model, endpoint, and call policy.

## Owners

- `core/trinity_contracts` defines provider pool and route decision contracts.
- `core/trinity_coordinator_core` derives route decisions and governance state.
- `bridges/trinity_bridge_inference` adapts selected slots to `:inference`
  provider calls.
- `apps/trinity_single_node` wires the standalone runtime profile.

## Mapping Rules

1. Keep stable agent and role ids in trace output.
2. Resolve provider pools through explicit config or command flags.
3. Keep live providers gated by `--allow-live` or application config.
4. Do not read provider credentials from library code.
5. Persist the chosen slot, role, provider pool, and model profile in traces.

Mock and local routes should remain available without network or provider
credentials.
