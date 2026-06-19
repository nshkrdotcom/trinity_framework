# Router Reflex

Router reflex makes route confidence operational inside the coordinator
Orchestrator. Margins and confidence bands are no longer trace-only metadata:
they select a deterministic execution path before provider dispatch.

## Behavior

`Trinity.Coordinator.ReflexPolicy` classifies each route decision as high,
medium, or low confidence.

- High confidence records `direct_dispatch` and dispatches the selected role
  without extra deliberation.
- Medium confidence records `normal_dispatch` and preserves the existing
  Orchestrator behavior.
- Low confidence records `thinker_then_verifier` and forces a Thinker turn
  before the final Verifier whenever the selected route is not already Thinker
  or Verifier.

The low-confidence path is immediate. It does not wait for an arbitrary failed
worker turn. If the selected route is Thinker, the Orchestrator dispatches
Thinker and forces Verifier on the next turn. If the selected route is Verifier,
the Orchestrator dispatches Verifier directly.

Reflex changes the role path, not the selected agent slot. A low-confidence
Worker route that selected `agent:1` dispatches `thinker` on `agent:1`, then
`verifier` on `agent:1`. This keeps the router-selected agent slot as execution
provenance while allowing role injection to add deliberation. Consumers that
need role-specific provider placement should express that in their provider
pool or agent-slot mapping, not by reinterpreting the reflex trace.

## Thresholds

The default mode is `profile_floor`. Thresholds are derived from
`Trinity.Sakana.MarginDefaults.defaults(runtime_profile)`:

```text
high_agent = floor.agent * 4.0
high_role = floor.role * 4.0
low_agent = floor.agent
low_role = floor.role
```

`absolute` mode is available for explicit testing and smoke commands. It uses
caller-supplied threshold values, or conservative documented defaults when no
value is supplied. Missing margins classify as medium by default; configure
`reflex_missing_margin: :low` or `--reflex-missing-margin low` to fail closed.

## Orchestrator Command

`mix trinity.orchestrator.demo` enables reflex by default and remains offline
with `--mock-provider`:

```bash
mix trinity.orchestrator.demo \
  --mock-provider \
  --runtime-profile mock_tiny \
  --max-turns 3 \
  --trace-out tmp/reflex_demo/trace.jsonl
```

Useful controls:

```bash
mix trinity.orchestrator.demo \
  --mock-provider \
  --runtime-profile mock_tiny \
  --max-turns 3 \
  --reflex \
  --reflex-margin-mode absolute \
  --reflex-low-agent-margin 999.0 \
  --reflex-low-role-margin 999.0 \
  --trace-out tmp/reflex_demo/low.jsonl \
  --json
```

Use at least two turns when intentionally forcing low confidence. A one-turn
low-confidence run can only dispatch the forced Thinker turn and should fail
with `:max_turns_reached` before Verifier can accept.

Disable reflex only for legacy comparisons:

```bash
mix trinity.orchestrator.demo \
  --mock-provider \
  --runtime-profile mock_tiny \
  --no-reflex \
  --trace-out tmp/reflex_demo/legacy.jsonl
```

Live provider execution is still opt-in through `--allow-live`. Reflex does not
add live provider behavior by default.

## Trace Event

The Orchestrator emits `reflex_decision` after `route_decision` and before the
turn-start budget snapshot. The event payload includes only route confidence
and policy fields:

```text
turn
route_hash
selected_agent_id
selected_role_id
original_role_name
original_role_atom
confidence_class
action
reason
agent_margin
role_margin
min_margin
confidence_band
thresholds
forced_sequence
next_role_override
reflex_enabled
```

The payload does not include raw messages, provider credentials, provider
headers, raw request bodies, raw response bodies, or endpoint authentication.

## Fitness Export

`mix trinity.sakana.fitness_export` preserves reflex metadata when a trace
contains `reflex_decision` records:

```json
{
  "route": {
    "reflex": {
      "confidence_class": "low",
      "action": "thinker_then_verifier",
      "reason": "low_margin",
      "forced_sequence": ["thinker", "verifier"]
    }
  }
}
```

The assembler copies this object through an allowlist. Older traces without
reflex records still export. Score formula `v1` is unchanged: reflex affects
fitness indirectly through verifier outcomes, revisions, latency, cost, and
budget pressure. A later formula can explicitly reward correct escalation or
penalize unnecessary escalation.

## Qwen Eval Report

The Qwen router prompt eval has an analysis-only reflex report:

```bash
cd examples/qwen_router_prompt_eval
mix run lib/qwen_router_prompt_eval.exs -- \
  --runtime-profile mock_tiny \
  --reflex-report \
  --reflex-trace-out ../../tmp/reflex_demo/qwen_reflex.jsonl
```

This classifies each eval route and emits paired `route_decision` and
`reflex_decision` records when requested. It does not affect expected agent or
role assertions, strict snapshot behavior, or pass/fail semantics.
