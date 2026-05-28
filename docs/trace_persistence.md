# Trace Persistence

Trace persistence is implemented through contracts and trace bridges. The root
framework keeps the event schema stable while applications choose durable
storage.

## Trace Surfaces

- `Trinity.Trace` contract data.
- `Trinity.Coordinator.TraceEvent` route and provider events.
- `Trinity.Bridge.Trace.JSONL` and `JsonlSink` for local JSONL output.
- AITrace-shaped payloads through `trinity_bridge_trace`.

## Rules

1. Hash route inputs and emitted decisions deterministically.
2. Redact provider-sensitive fields before writing trace events.
3. Keep local JSONL useful for mock and CI flows.
4. Let applications choose database or object-store persistence.

Operator commands accept `--trace-out` where route/demo flows emit trace files.
