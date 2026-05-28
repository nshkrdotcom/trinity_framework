# Trinity Live Inspect

Purpose: run V5 Trinity Crucible inspect and matrix eval in trace replay and
live hosted-runtime modes.

## What this covers

The inspect task evaluates Crucible JSONL traces offline or invokes the hosted
native worker when `--live` is selected. Matrix eval can replay a trace file,
directory, or glob, and can run live prompt-eval limits against an actual hosted
model. Routing decisions are derived from declared trace capabilities and policy
evidence, then written as policy and route decision artifacts under the V5
artifact root.

## Quickstart

Replay a synthetic Python-shaped fixture:

```bash
mix trinity.crucible.inspect --trace runs/synthetic_python_gpt2_trace.jsonl --artifact-root tmp/crucible_v5
```

Replay all native V5 traces:

```bash
mix trinity.crucible.matrix_eval --trace tmp/crucible_v5/traces/native --artifact-root tmp/crucible_v5
```

Run the live hosted native provider:

```bash
TRINITY_CRUCIBLE_LIVE=true mix trinity.crucible.inspect --live --model-id gpt2 --backend binary --artifact-root tmp/crucible_v5 --prompt "Hi"
```

Run the live matrix ladder:

```bash
TRINITY_CRUCIBLE_LIVE=true mix trinity.crucible.matrix_eval --live --limit 3 --artifact-root tmp/crucible_v5 --stability-repeats 3
TRINITY_CRUCIBLE_LIVE=true mix trinity.crucible.matrix_eval --live --limit 10 --artifact-root tmp/crucible_v5
TRINITY_CRUCIBLE_LIVE=true mix trinity.crucible.matrix_eval --live --limit 37 --artifact-root tmp/crucible_v5
```

Useful live model options:

```bash
--model-id gpt2
--model-id distilgpt2
--model-id hf-internal-testing/tiny-random-distilbert --architecture for_sequence_classification
--model-id trl-internal-testing/tiny-Qwen3ForCausalLM
```

## Related guides

- [Crucible Path](crucible_path.md)
- [Operations QC](operations_qc.md)
