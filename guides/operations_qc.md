# Operations And QC

The root repository is done only if the root project proves the aggregate. Green
sub-packages are not enough.

## Required Root Gates

```bash
mix test
mix ci
mix credo --strict
mix dialyzer --format short
mix docs
```

Expected result: no warnings, no errors, no Credo issues, and no Dialyzer
issues.

## Operator Gates

```bash
mix trinity.gates --summary-out tmp/trinity_gates.json
mix trinity.env.check
mix help --search trinity
```

`mix help --search trinity` must list 23 commands, including
`mix trinity.crucible.inspect`, `mix trinity.crucible.matrix_eval`,
`mix trinity.eval`, `mix trinity.orchestrator.demo`, and
`mix trinity.sakana.fitness_export`.

## Fitness Export Smoke

```bash
mix trinity.orchestrator.demo \
  --mock-provider \
  --runtime-profile mock_tiny \
  --max-turns 1 \
  --trace-out tmp/sakana_fitness_smoke/orchestrator.jsonl

mix trinity.sakana.fitness_export \
  --trace tmp/sakana_fitness_smoke/orchestrator.jsonl \
  --out tmp/sakana_fitness_smoke/fitness.jsonl \
  --manifest-out tmp/sakana_fitness_smoke/manifest.json \
  --json

mix trinity.sakana.fitness_inspect \
  --fitness tmp/sakana_fitness_smoke/fitness.jsonl \
  --manifest tmp/sakana_fitness_smoke/manifest.json \
  --out tmp/sakana_fitness_smoke/inspect.json \
  --json

mix trinity.sakana.fitness_replay \
  --fitness tmp/sakana_fitness_smoke/fitness.jsonl \
  --manifest tmp/sakana_fitness_smoke/manifest.json \
  --out tmp/sakana_fitness_smoke/replay.json \
  --json

mix trinity.reflex.calibrate \
  --fitness tmp/sakana_fitness_smoke/fitness.jsonl \
  --out tmp/sakana_fitness_smoke/reflex_calibration.json \
  --json

test -s tmp/sakana_fitness_smoke/fitness.jsonl
test -s tmp/sakana_fitness_smoke/manifest.json
test -s tmp/sakana_fitness_smoke/inspect.json
test -s tmp/sakana_fitness_smoke/replay.json
test -s tmp/sakana_fitness_smoke/reflex_calibration.json
```

The mock smoke must not require a network, CUDA, an artifact fetch, or provider
credentials. JSON mode must print only one machine-readable summary. A first
verifier revision must be recorded as `revision_count: 1`, with the matching
budget snapshot reporting one verifier revision.

No-CUDA Sakana checks:

```bash
mix trinity.sakana.export_adapted --dry-run --json
mix trinity.sakana.parity_sample --semantic-only --no-cuda
mix trinity.sakana.large_tensor_chunks --no-cuda
```

## Package Gates

Run package gates after package-local changes:

```bash
for app in \
  core/trinity_contracts \
  core/trinity_coordinator_core \
  core/trinity_sakana_contracts \
  core/trinity_sakana_pipeline \
  bridges/trinity_bridge_self_hosted_inference \
  bridges/trinity_bridge_inference \
  bridges/trinity_bridge_trace \
  apps/trinity_single_node \
  tools/trinity_ops \
  examples/qwen_router_prompt_eval \
  examples/crucible_route
do
  (cd "$app" && mix ci)
done
```

Router-fabric changes must include focused
`core/trinity_coordinator_core` tests for class-to-profile mapping, unmapped
class rejection, and bounded route receipt shape before root gates run.

## Heavy Gates

Run these on a CUDA host with the artifact bundle materialized:

```bash
mix trinity.artifact.fetch
mix trinity.hitl.gpu
mix trinity.hitl.vector
mix trinity.hitl.head_route
mix trinity.hitl.base_qwen
mix trinity.hitl.adapted
```

Run eval:

```bash
cd examples/qwen_router_prompt_eval
XLA_TARGET=cuda12 mix run lib/qwen_router_prompt_eval.exs -- \
  --snapshot fixtures/qwen_router_prompt_eval_logits.json \
  --determinism-runs 2
```

## Commit Discipline

For checklist-driven work, commit and push at phase boundaries. Do not leave
generated artifact bundles staged. The large default artifact directory is
ignored by `.gitignore`.
