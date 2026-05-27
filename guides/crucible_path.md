# Crucible Path

Trinity has two route paths:

- `:legacy_route_logits` keeps the current adapted-Qwen/Sakana route-head path.
- `:crucible` builds a model-agnostic Crucible tap plan, writes a bounded
  `CrucibleSignalTrace.ForwardTrace`, creates a `CruciblePolicy.RouteDecision`,
  and adapts it into `Trinity.Coordinator.RouteDecision`.

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
- `Trinity.Crucible.DiffReport` compares route decisions only. It does not
  compare generated text unless both paths use the same generator.

## Commands

```bash
mix trinity.crucible.inspect --runtime-profile mock_tiny
mix trinity.crucible.matrix_eval --runtime-profile mock_tiny
mix trinity.eval qwen_router_prompt_eval
mix trinity.eval qwen_router_prompt_eval --via crucible
```

The matrix eval prints exact role matching, target overlap, confidence-band
agreement, decision stability, trajectory margins, safety regressions, format
strictness, and warmed post-processing overhead. Strict acceptance requires
zero safety regressions, at least 85% role concordance, less than 8% warmed
post-processing overhead, and 100% format strictness.

## Programmatic Use

```elixir
messages = [%{"role" => "user", "content" => "Route this request."}]

{:ok, result} =
  Trinity.SingleNode.route(messages,
    via: :crucible,
    runtime_profile: :mock_tiny,
    trace_path: "tmp/trinity_crucible.jsonl"
  )

result.decision
result.crucible_trace
result.tap_plan
```

For the current Trinity profile, `via: :crucible` adapts existing route-logit
evidence into Crucible records. A runtime that natively emits Crucible traces
can supply the same `CruciblePolicy.RouteDecision` contract without changing
Trinity's decision adapter.
