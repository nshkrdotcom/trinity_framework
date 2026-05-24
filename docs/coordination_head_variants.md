# Coordination Head Variants

The canonical adapted profile uses a linear routing head over the Qwen hidden
state. The framework keeps that shape in contracts so future head variants can
be compared without changing coordinator APIs.

## Canonical Shape

- Base model: `Qwen/Qwen3-0.6B`
- Hidden size: `1024`
- Output count: `10`
- Source layer: `26`
- Source tensor: `trinity_router_es_vector`

`core/trinity_sakana_contracts` owns the profile and router-head specs.
`core/trinity_sakana_pipeline` owns export, import, and parity mechanics.

## Variant Checklist

1. Add a profile contract or explicit variant metadata.
2. Regenerate or import the artifact bundle.
3. Record source vector shape, split counts, and head tensor shape.
4. Run parity sample and router trace checks.
5. Refresh eval snapshots only after reviewing route changes.
