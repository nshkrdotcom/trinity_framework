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
