# Sakana Adapted Artifact Plan

The adapted artifact bundle is generated or fetched outside git and verified by
`priv/sakana_trinity/artifact_pin.json`.

## Bundle Contents

- `manifest.json`
- `router_head.safetensors`
- selected checkpoint tensor safetensors
- parity/reference material under `priv/sakana_trinity/reference`

## Generate

Generate or select a router vector through the external evolution loop first:

1. Produce traces with `mix trinity.orchestrator.demo` or Qwen eval
   `--trace-out`.
2. Run `mix trinity.sakana.fitness_export`.
3. Run `mix trinity.sakana.fitness_inspect`,
   `mix trinity.sakana.fitness_replay`, and `mix trinity.reflex.calibrate`.
4. Train externally and evaluate returned candidates with
   `mix trinity.sakana.candidate_eval`.
5. Place the reviewed vector at
   `priv/sakana_trinity/artifacts/trinity_router_es_vector.safetensors`.

```bash
XLA_TARGET=cuda12 mix trinity.sakana.export_adapted \
  --out priv/sakana_trinity/adapted_qwen3_0_6b_layer26 \
  --source-vector priv/sakana_trinity/artifacts/trinity_router_es_vector.safetensors \
  --force
```

## Verify

```bash
mix trinity.sakana.import_python --json
mix trinity.sakana.parity_sample --semantic-only --no-cuda
mix trinity.sakana.large_tensor_chunks --no-cuda
```

Publish only after manifest checksums and eval outputs have been reviewed.
