# Adaptation Readiness Loop

TRINITY owns evidence production and acceptance gates. External training owns
evolution, optimization, and weight mutation. The adaptation readiness loop
connects those boundaries without letting candidate evaluation overwrite
accepted artifacts.

## 1. Produce Evidence

Use Orchestrator-backed traces or Qwen eval traces:

```bash
mix trinity.orchestrator.demo \
  --mock-provider \
  --runtime-profile mock_tiny \
  --max-turns 3 \
  --trace-out tmp/adaptation_readiness/orchestrator.jsonl \
  --json
```

## 2. Export Fitness

```bash
mix trinity.sakana.fitness_export \
  --trace tmp/adaptation_readiness/orchestrator.jsonl \
  --out tmp/adaptation_readiness/fitness.jsonl \
  --manifest-out tmp/adaptation_readiness/manifest.json \
  --json
```

The export is allowlisted and hash-content by default. It does not train or
mutate weights.

## 3. Inspect Dataset Health

```bash
mix trinity.sakana.fitness_inspect \
  --fitness tmp/adaptation_readiness/fitness.jsonl \
  --manifest tmp/adaptation_readiness/manifest.json \
  --out tmp/adaptation_readiness/inspect.json \
  --json
```

The report verifies the manifest digest, scans for forbidden secret-bearing
fields, counts labels, summarizes runtime/artifact/reflex coverage, and assigns
a dataset status.

## 4. Replay Score Formula

```bash
mix trinity.sakana.fitness_replay \
  --fitness tmp/adaptation_readiness/fitness.jsonl \
  --manifest tmp/adaptation_readiness/manifest.json \
  --out tmp/adaptation_readiness/replay.json \
  --json
```

Replay recomputes score-v1 from each example and reports score/label
mismatches, component summaries, group summaries, and reflex economics.

## 5. Calibrate Reflex Thresholds

```bash
mix trinity.reflex.calibrate \
  --fitness tmp/adaptation_readiness/fitness.jsonl \
  --out tmp/adaptation_readiness/reflex_calibration.json \
  --json
```

Calibration sweeps deterministic threshold multipliers over exported examples.
It reports recommendations only; it does not mutate `ReflexPolicy` defaults.

## 6. Evaluate Candidate Routes

```bash
mix trinity.sakana.candidate_eval \
  --fitness tmp/adaptation_readiness/fitness.jsonl \
  --manifest tmp/adaptation_readiness/manifest.json \
  --candidate-routes tmp/candidates/candidate_routes.jsonl \
  --out tmp/adaptation_readiness/candidate_proposal.json \
  --json
```

Candidate route evaluation compares explicit candidate route decisions against
baseline fitness examples. Positive examples whose selected agent or role
regresses are rejected.

## 7. Preflight Candidate Vectors

```bash
mix trinity.sakana.candidate_eval \
  --fitness tmp/adaptation_readiness/fitness.jsonl \
  --manifest tmp/adaptation_readiness/manifest.json \
  --candidate-vector tmp/candidates/trinity_router_es_vector.safetensors \
  --candidate-vector-key router_vector \
  --out tmp/adaptation_readiness/candidate_vector_proposal.json \
  --json
```

Vector mode validates SafeTensors metadata, file digest, key presence, element
count, and router-vector split shape. It does not call
`mix trinity.sakana.export_adapted` and does not overwrite accepted artifacts.

## 8. Continue Through Existing Gates

Only after a proposal is accepted for the next stage should operators run the
existing export and acceptance path:

```bash
mix trinity.sakana.export_adapted --dry-run --json
mix trinity.sakana.parity_sample --semantic-only --no-cuda
mix trinity.sakana.large_tensor_chunks --no-cuda
```

On CUDA hosts, also run the Qwen eval and HITL checks documented in
`guides/operations_qc.md`.
