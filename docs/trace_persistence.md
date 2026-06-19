# Trace Persistence

Trace persistence is implemented through contracts and trace bridges. The root
framework keeps the event schema stable while applications choose durable
storage.

## Trace Surfaces

- `Trinity.Trace` contract data.
- `Trinity.Coordinator.TraceEvent` route and provider events.
- `Trinity.Bridge.Trace.JSONL` and `JsonlSink` for local JSONL output.
- AITrace-shaped payloads through `trinity_bridge_trace`.
- Orchestrator lifecycle events used by Sakana fitness export:
  `route_decision`, dispatch start/finish, `verifier_result`, budget snapshots,
  and terminal run events.

## Rules

1. Hash route inputs and emitted decisions deterministically.
2. Redact provider-sensitive fields before writing trace events.
3. Keep local JSONL useful for mock and CI flows.
4. Let applications choose database or object-store persistence.
5. Derive artifact identity from the executed runtime's verified manifest and
   pin; caller-supplied identity labels are assertions, not trace overrides.
6. Prefix machine-local artifact paths with `local_` so export tooling can
   identify and redact them.

Operator commands accept `--trace-out` where route/demo flows emit trace files.
`mix trinity.orchestrator.demo` is the fitness-bearing producer; the legacy
smoke loop is not treated as Orchestrator outcome evidence.

`mix trinity.sakana.fitness_export` streams these JSONL records and builds each
example by copying a fixed field allowlist. It never merges source payloads,
headers, credentials, raw provider bodies, or endpoint authentication into the
dataset.

Verifier event revision counts are cumulative after the current decision is
applied. For a revision, `verifier_result.revision_count` and the following
`after_verifier_revision` budget snapshot agree; accepted decisions do not
increment the counter. Fitness scoring therefore attributes revision cost to
the route that caused it.

The external PyTorch trace provider is tracked at
`tools/python/crucible_torch_trace.py`. The framework boundary test scans that
location and rejects a legacy root-level `python/` provider directory.
