# Sakana SVD Byte-Match Rigor Plan

Functional parity is the required gate. Byte-for-byte parity is diagnostic and
can vary by backend, dtype, and SVD implementation.

## Required Checks

- Stage names and selected tensor manifests match expectations.
- Required stages pass configured max and mean absolute-error tolerances.
- Shape and dtype checks pass.
- Route hashes remain stable for committed eval snapshots.

## Diagnostic Checks

- Byte match for source tensors.
- Alternate hashes as `f32` and `bf16`.
- Large tensor chunk replay against Python reports.

Use `mix trinity.sakana.parity_sample` for compact diagnostics and
`mix trinity.sakana.large_tensor_chunks` for chunked large tensor replay.
