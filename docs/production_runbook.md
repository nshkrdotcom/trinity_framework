# Production Runbook

Production operation starts from a verified artifact pin and explicit runtime
configuration.

## Bringup

1. Fetch the pinned artifact bundle.
2. Run root framework gates.
3. Run CUDA visibility and adapted-bundle checks.
4. Run the 37-case Qwen router eval.
5. Enable live provider routing only after mock and self-hosted paths pass.

```bash
mix trinity.artifact.fetch
mix ci
mix trinity.gates
XLA_TARGET=cuda12 mix trinity.hitl.gpu
XLA_TARGET=cuda12 mix trinity.hitl.vector
XLA_TARGET=cuda12 mix trinity.hitl.head_route
XLA_TARGET=cuda12 mix trinity.hitl.base_qwen
XLA_TARGET=cuda12 mix trinity.hitl.adapted
```

Live provider credentials belong to the deploying application or runtime
configuration boundary.

## Artifact Identity

Runtime provenance is resolved from the selected artifact root, its
`manifest.json`, and its verified artifact pin. Runtime options cannot replace
manifest-derived model, layout, route-head, tensor-count, or vector-shape
facts.

Identity label options such as `:model_id`, `:artifact_ref`,
`:artifact_repo`, and `:artifact_revision` are assertions. Runtime loading
fails with `:artifact_identity_mismatch` when an assertion differs from the
resolved artifact. Options that attempt to supply structural provenance fail
with `:invalid_artifact_identity_options`.

Use `:artifact_root` to select an artifact and `:artifact_pin_path` only when a
nonstandard pin location is required. Do not use runtime options to describe
what an artifact is; update and verify its manifest and pin instead.
