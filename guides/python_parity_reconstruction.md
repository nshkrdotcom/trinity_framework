# Python Parity Reconstruction

Python parity reconstruction exists to compare historical Sakana/Python
semantics with the framework-native artifact pipeline.

## Reference Files

```text
priv/sakana_trinity/reference/sakana_python_reference_manifest.json
priv/sakana_trinity/reference/sakana_decompose_model.original.py
priv/sakana_trinity/scripts/debug_sakana_parity_sample.py
priv/sakana_trinity/scripts/debug_sakana_large_tensor_chunks.py
priv/sakana_trinity/scripts/debug_sakana_router_trace.py
```

## Semantic Export From Python

```bash
uv run --python 3.11 \
  --with torch==2.7.1 \
  --with transformers==4.55.2 \
  --with accelerate==1.6.0 \
  --with numpy \
  --with safetensors \
  python priv/sakana_trinity/scripts/export_sakana_trinity_safetensors.py \
    --svd-weights path/to/svd_weights.pt \
    --output-dir tmp/sakana_parity/python_semantic_export
```

If the original SVD weights are unavailable:

```bash
python3 priv/sakana_trinity/scripts/export_sakana_trinity_safetensors.py \
  --decompose-if-missing
```

That path is heavier and may not reproduce historical hashes.

## Import Into Framework Artifacts

```bash
mix trinity.sakana.import_python \
  --source-dir tmp/sakana_parity/python_semantic_export \
  --manifest trinity_sakana_export_manifest.json \
  --reference priv/sakana_trinity/reference/sakana_python_reference_manifest.json \
  --out tmp/sakana_parity/adapted_artifacts_from_python \
  --force \
  --json
```

## What Counts As Proof

Release readiness is established by:

- semantic import/export checks;
- large tensor chunk checks;
- parity sample checks;
- CUDA 37-case route-decision eval.

Strict historical Python byte-for-byte reproduction is a separate provenance
gate. It requires the historical Python environment and original weights.

