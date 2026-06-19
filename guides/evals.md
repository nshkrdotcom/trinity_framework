# Evals

The primary eval is the 37-case Qwen router prompt eval in:

```text
examples/qwen_router_prompt_eval
```

## Run The Eval

```bash
cd examples/qwen_router_prompt_eval
XLA_TARGET=cuda12 mix run lib/qwen_router_prompt_eval.exs -- \
  --snapshot fixtures/qwen_router_prompt_eval_logits.json \
  --determinism-runs 2
```

Expected result:

```text
PASS qwen_router_prompt_eval
```

## List Cases

```bash
mix run lib/qwen_router_prompt_eval.exs -- --list-cases
```

## Run One Case

```bash
XLA_TARGET=cuda12 mix run lib/qwen_router_prompt_eval.exs -- \
  --case planner.basic \
  --snapshot fixtures/qwen_router_prompt_eval_logits.json
```

## Write A New Snapshot

```bash
XLA_TARGET=cuda12 mix run lib/qwen_router_prompt_eval.exs -- \
  --snapshot-out tmp/qwen_router_prompt_eval_logits.json \
  --determinism-runs 2
```

Only update committed snapshots after reviewing route changes. Stable fields
include agent id, role id, token count, and transcript hash. Route hash is used
for in-process determinism and diagnostics.

## Write Fitness Source Traces

```bash
mix run lib/qwen_router_prompt_eval.exs -- \
  --runtime-profile mock_tiny \
  --trace-out ../../tmp/sakana_fitness/qwen_eval_trace.jsonl
```

This writes `route_decision` and `route_eval_result` records per case while
leaving snapshot output unchanged. It does not score fitness. Export from the
framework root with `mix trinity.sakana.fitness_export`; eval `ok`, `fail`, and
`report` statuses map to accepted, rejected, and unknown outcomes during
assembly.

The trace writer emits two records per case and keeps determinism replays on the
same case identity. Mock-profile cases are report-only evidence; CUDA Qwen
snapshot acceptance remains the release-grade route proof.

## Reflex Classification Report

Router reflex can be reported during the eval without changing strict route
assertions:

```bash
mix run lib/qwen_router_prompt_eval.exs -- \
  --runtime-profile mock_tiny \
  --reflex-report \
  --reflex-trace-out ../../tmp/reflex_smoke/qwen_reflex.jsonl
```

`--reflex-report` prints per-case confidence class/action and aggregate counts.
`--reflex-trace-out` writes paired `route_decision` and `reflex_decision`
records for downstream inspection. Neither flag changes expected agent ids,
role ids, snapshot comparison, determinism checks, or pass/fail semantics.

## Debug Native Logs

```bash
XLA_TARGET=cuda12 mix run lib/qwen_router_prompt_eval.exs -- \
  --debug-native-logs \
  --snapshot fixtures/qwen_router_prompt_eval_logits.json
```

Normal mode stores native compiler/runtime logs under:

```text
tmp/examples/qwen_router_prompt_eval.native.log
```

## Root Eval Wrapper

The framework root also exposes smoke-friendly route eval wrappers:

```bash
mix trinity.eval qwen_router_prompt_eval
mix trinity.crucible.matrix_eval --runtime-profile mock_tiny
```

With no explicit profile these commands use `mock_tiny`. A passing mock report
means:

```text
Runtime profile: mock_tiny
Qwen runtime: not loaded
Contract-path eval only
```

That is useful for contract strictness and trace/evidence plumbing, but it is
not adapted-Qwen proof.

Run the wrapper against the Qwen/Sakana route runtime with:

```bash
XLA_TARGET=cuda12 mix trinity.eval qwen_router_prompt_eval \
  --runtime-profile cuda_exla
```

The wrapper report covers route decisions, confidence bands, trajectory
margins, expected-role diagnostics, trace-derived evidence, and contract
strictness. It does not compare generated text.

Keep two acceptance levels separate:

- Route/margin/determinism acceptance belongs to the runtime eval path.
- Strict logits snapshot acceptance belongs to the direct example fixture:

```bash
cd examples/qwen_router_prompt_eval
XLA_TARGET=cuda12 mix run lib/qwen_router_prompt_eval.exs -- \
  --snapshot fixtures/qwen_router_prompt_eval_logits.json \
  --determinism-runs 2
```
