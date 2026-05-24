# Production Qwen SLM Profile

The production Qwen profile is represented by contracts and loaded by the
self-hosted inference bridge. The root framework assembles those pieces but does
not move external runtime ownership into the root facade.

## Profile Contract

- Profile: `qwen3_0_6b_layer26`
- Base model repo: `Qwen/Qwen3-0.6B`
- Hidden size: `1024`
- Selected layer indices: `[26]`
- Router tensor: `trinity_router_es_vector`

## Runtime Checks

```bash
XLA_TARGET=cuda12 mix trinity.hitl.base_qwen
XLA_TARGET=cuda12 mix trinity.hitl.head_route
XLA_TARGET=cuda12 mix trinity.hitl.adapted
```

Use `mock_tiny` for CPU-only smoke work and CUDA profiles for adapted runtime
acceptance.
