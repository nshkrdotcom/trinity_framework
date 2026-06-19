# Artifacts And Export

The framework supports both consuming the published bundle and regenerating the
adapted safetensors artifacts.

## Important Files

```text
priv/sakana_trinity/artifact_pin.json
priv/sakana_trinity/artifacts/sakana_model_iter_60.npy
priv/sakana_trinity/artifacts/trinity_router_es_vector.safetensors
priv/sakana_trinity/reference/sakana_python_reference_manifest.json
priv/sakana_trinity/reference/sakana_decompose_model.original.py
priv/sakana_trinity/scripts/export_sakana_trinity_safetensors.py
```

The generated runtime bundle lands at:

```text
priv/sakana_trinity/adapted_qwen3_0_6b_layer26
```

## Fitness To External ES

```bash
mix trinity.orchestrator.demo --mock-provider --runtime-profile mock_tiny \
  --trace-out tmp/sakana_fitness/orchestrator.jsonl

mix trinity.sakana.fitness_export \
  --trace tmp/sakana_fitness/orchestrator.jsonl \
  --out tmp/sakana_fitness/fitness.jsonl \
  --manifest-out tmp/sakana_fitness/manifest.json
```

An external ES trainer consumes that dataset and produces a new
`trinity_router_es_vector.safetensors`. The framework then uses the existing
adapted export, parity, and eval gates below. Fitness export itself never
changes weights.

## Export Adapted Safetensors

Full export:

```bash
XLA_TARGET=cuda12 mix trinity.sakana.export_adapted
```

Dry run:

```bash
mix trinity.sakana.export_adapted --dry-run --json
```

Single tensor smoke:

```bash
XLA_TARGET=cuda12 mix trinity.sakana.export_adapted --only-index 1 --force
```

Resume:

```bash
XLA_TARGET=cuda12 mix trinity.sakana.export_adapted --resume
```

Useful options:

- `--out PATH`
- `--source-vector PATH`
- `--tensor-name NAME`
- `--profile PROFILE`
- `--runtime-profile PROFILE`
- `--force`
- `--resume`
- `--skip-existing`
- `--svd-compute-type f32`

## Import Python Semantic Export

```bash
mix trinity.sakana.import_python \
  --source-dir tmp/sakana_parity/python_semantic_export \
  --manifest trinity_sakana_export_manifest.json \
  --reference priv/sakana_trinity/reference/sakana_python_reference_manifest.json \
  --out tmp/sakana_parity/adapted_artifacts_from_python \
  --force \
  --json
```

## Large Tensor Chunk Checks

```bash
mix trinity.sakana.large_tensor_chunks \
  --python-report priv/sakana_trinity/reference/sakana_python_reference_manifest.json \
  --out tmp/sakana_large_tensor_chunks.json \
  --chunk-rows 2048 \
  --no-cuda
```

## Parity Sample

```bash
mix trinity.sakana.parity_sample \
  --semantic-only \
  --no-cuda \
  --out tmp/sakana_parity_sample.json
```

Strict historical byte reproduction requires the original Python provenance and
the original SVD weights. The framework release-readiness path is semantic
import/export plus CUDA route-decision parity.
