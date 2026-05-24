# Sakana SVD Parity Debug Checklist

Use this when Elixir/Python artifact parity diverges.

1. Confirm the source vector file and tensor name.
2. Confirm selected layer indices and tensor manifest order.
3. Compare source tensor summaries before decomposition.
4. Compare `u`, `s`, `v`, scaled singular values, normalization, and final
   tensors.
5. Run semantic-only checks before CUDA checks.
6. Run one selected tensor with `--only-index`.
7. Check large tensor chunk reports for localized drift.

Useful commands:

```bash
mix trinity.sakana.export_adapted --dry-run --json
mix trinity.sakana.parity_sample --semantic-only --no-cuda
mix trinity.sakana.large_tensor_chunks --no-cuda
```
