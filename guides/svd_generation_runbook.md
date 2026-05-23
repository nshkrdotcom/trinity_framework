# SVD Generation Runbook

This runbook covers the Sakana SVD material that feeds the adapted artifact
export.

## Inputs

```text
priv/sakana_trinity/artifacts/sakana_model_iter_60.npy
priv/sakana_trinity/artifacts/trinity_router_es_vector.safetensors
```

Optional historical input:

```text
path/to/svd_weights.pt
```

Do not commit or upload private `.pt` provenance files unless a release process
explicitly asks for them.

## Convert Router Vector

If the `.npy` vector changes, convert it to safetensors:

```bash
python3 priv/sakana_trinity/scripts/convert_router_vector_to_safetensors.py
```

## Debug SVD Sample

```bash
python3 priv/sakana_trinity/scripts/debug_sakana_parity_sample.py \
  --model-torch-dtype float32 \
  --svd-weights path/to/svd_weights.pt \
  --out tmp/sakana_parity/python_sample_trace.json \
  --write-components-dir tmp/sakana_parity/python_components
```

## All-Selected Tensor Diagnostic

```bash
python3 priv/sakana_trinity/scripts/debug_sakana_parity_sample.py \
  --model-torch-dtype float32 \
  --svd-weights path/to/svd_weights.pt \
  --all-selected-tensors \
  --out tmp/sakana_parity/python_sample_trace.json \
  --write-components-dir tmp/sakana_parity/python_components
```

## Framework Export

```bash
XLA_TARGET=cuda12 mix trinity.sakana.export_adapted --force
```

Use `--dry-run --json` before expensive exports when validating options.

