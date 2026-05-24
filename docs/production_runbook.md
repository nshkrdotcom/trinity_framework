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
mix trinity.gates --fast
XLA_TARGET=cuda12 mix trinity.hitl.gpu
XLA_TARGET=cuda12 mix trinity.hitl.vector
XLA_TARGET=cuda12 mix trinity.hitl.head_route
XLA_TARGET=cuda12 mix trinity.hitl.base_qwen
XLA_TARGET=cuda12 mix trinity.hitl.adapted
```

Live provider credentials belong to the deploying application or runtime
configuration boundary.
