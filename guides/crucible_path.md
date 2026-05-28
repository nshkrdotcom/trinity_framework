# Crucible Path

Trinity has one route path for Crucible evidence. It builds a model-agnostic
tap plan, writes a bounded `%Crucible.ForwardTrace{}`, evaluates Crucible
policies, and adapts the result into `Trinity.Coordinator.RouteDecision`.

The Crucible libraries are reusable and not tied to Qwen, Qwen3, or the
modified Trinity 0.6B profile. Qwen remains a Trinity runtime profile and eval
fixture, not a Crucible library assumption.

## Modules

- `Trinity.Crucible.RequestContext` is the request contract for route-time tap
  selection.
- `Trinity.Crucible.TapPlanBuilder` maps task type, turn, budget, and runtime
  profile metadata into a `CrucibleTap.TapPlan`.
- `Trinity.Crucible.TraceAdapter` converts route evidence into bounded
  Crucible trace records.
- `Trinity.Crucible.DecisionAdapter` maps `CruciblePolicy.RouteDecision` into
  the enforced Trinity route-decision fields with deterministic fabricated
  refs.

## Commands

```bash
mix trinity.crucible.inspect --runtime-profile mock_tiny
mix trinity.crucible.matrix_eval --runtime-profile mock_tiny
mix trinity.eval qwen_router_prompt_eval
```

The matrix eval prints expected-role diagnostics, confidence-band coverage,
trajectory margins, safety expectations, and contract strictness. Strict smoke
acceptance requires every row to contain a valid route decision and bounded
Crucible trace evidence.

## Programmatic Use

```elixir
messages = [%{"role" => "user", "content" => "Route this request."}]

{:ok, result} =
  Trinity.SingleNode.route(messages,
    runtime_profile: :mock_tiny,
    trace_path: "tmp/trinity_crucible.jsonl"
  )

result.decision
result.crucible_trace
result.tap_plan
```

The route result carries the Trinity decision, the Crucible trace, and the tap
plan used to produce that trace. A runtime that natively emits Crucible traces
can supply the same policy-decision contract without changing Trinity's
decision adapter.
