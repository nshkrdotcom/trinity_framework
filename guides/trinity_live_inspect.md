# Trinity Live Inspect

Purpose: run V4 Trinity Crucible inspect in trace replay and live modes.

## What this covers

The inspect task evaluates a v4 JSONL trace offline or invokes the hosted native
worker when `--live` is selected. Routing decisions are derived from declared
trace capabilities and policy evidence.

## Quickstart

Replay a synthetic Python-shaped fixture:

```bash
mix trinity.crucible.inspect --trace runs/synthetic_python_gpt2_trace.jsonl
```

Run the live hosted native provider:

```bash
TRINITY_CRUCIBLE_LIVE=true mix trinity.crucible.inspect --live --prompt "Hi"
```

Run the live matrix smoke:

```bash
TRINITY_CRUCIBLE_LIVE=true mix trinity.crucible.matrix_eval --live --limit 3
```

## Related guides

- [Crucible Path](crucible_path.md)
- [Operations QC](operations_qc.md)
