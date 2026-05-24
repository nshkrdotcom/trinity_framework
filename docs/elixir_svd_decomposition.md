# Elixir SVD Decomposition

SVD/SVF math is owned by `crucible_factorization`. The framework calls it
through explicit package APIs and keeps product-specific tensor names in
framework code.

## Flow

1. Select decomposable tensors from the model parameter tree.
2. Decompose tensors with `CrucibleFactorization.SVD.decompose_tensors/2`.
3. Split the source router vector into scale offsets and head weights.
4. Reconstruct adapted tensors with `reconstruct_tensors/3`.
5. Write outputs and manifest data through pipeline artifact IO.

## Quality Checks

```bash
mix trinity.sakana.export_adapted --dry-run --json
mix trinity.sakana.parity_sample --semantic-only --no-cuda
mix trinity.sakana.large_tensor_chunks --no-cuda
```

CUDA runs should use `XLA_TARGET=cuda12` and the adapted artifact bundle.
