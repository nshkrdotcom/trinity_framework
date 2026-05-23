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
mix trinity.gates --fast --summary-out tmp/trinity_gates.json
mix trinity.env.check
mix help --search trinity
```

`mix help --search trinity` must list 17 commands.

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
  examples/qwen_router_prompt_eval
do
  (cd "$app" && mix ci)
done
```

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

