# Sakana Fitness Export

TRINITY fitness export closes the evidence-to-evolution data loop without
training or mutating model weights. The framework produces deterministic,
schema-versioned examples; an external ES trainer remains responsible for
creating a new router vector or head.

## 1. Produce Orchestrator Evidence

Use the real coordinator Orchestrator with the local mock route/runtime and
provider lanes:

```bash
mix trinity.orchestrator.demo \
  --runtime-profile mock_tiny \
  --mock-provider \
  --max-turns 3 \
  --trace-out tmp/orchestrator_demo/trace.jsonl
```

The command uses `Trinity.Coordinator.Orchestrator.run_loop/2`, including its
role injection, verifier parsing, revision counters, provider budgets, latency
checks, and terminal status. Live provider execution is rejected unless
`--allow-live` is explicit.

The trace contains route decisions, reflex decisions, dispatch start/finish
records, verifier results, budget snapshots, and run completion or failure.
Hash content is the default; credentials, request headers, provider payloads,
and raw prompts are not fitness fields.

Router reflex makes confidence operational before dispatch. High-confidence
routes record `direct_dispatch`, medium-confidence routes record
`normal_dispatch`, and low-confidence routes record `thinker_then_verifier` and
force Thinker before Verifier. The exporter preserves this metadata under
`route.reflex` when present, but the score-v1 formula still uses verifier
outcome, margins, revisions, latency, cost, and budget state. Reflex affects
fitness indirectly through those outcomes.

`verifier_result.revision_count` is the cumulative count after applying that
decision. A first `revise`/`revised` result therefore records `1`; an accepted
result leaves the count unchanged. The matching `after_verifier_revision`
budget snapshot carries the same count. The assembler prefers this
self-contained verifier value, so the score penalty is assigned to the route
whose verifier result requested the revision.

## 2. Export Fitness Examples

```bash
mix trinity.sakana.fitness_export \
  --trace tmp/orchestrator_demo/trace.jsonl \
  --out tmp/sakana_fitness/fitness.jsonl \
  --manifest-out tmp/sakana_fitness/manifest.json \
  --json
```

`--trace` is repeatable. The default export uses:

- JSONL format.
- Hash-only input content.
- Score formula `v1`.
- `profile_floor` margin normalization from
  `Trinity.Sakana.MarginDefaults`.
- Positive threshold `0.67` and negative threshold `0.33`.
- An explicit allowlist copy from trace records.

Use `--dry-run` to parse, assemble, score, and compute digests without writing
files. `--skip-invalid` reports malformed lines instead of failing. Use
`--content full` only for deliberately captured traces whose route records
contain `input_content`; the default never emits raw prompt content.

## Eval Evidence

The Qwen router eval can emit route and eval-result records without scoring:

```bash
cd examples/qwen_router_prompt_eval
mix run lib/qwen_router_prompt_eval.exs -- \
  --runtime-profile mock_tiny \
  --trace-out ../../tmp/sakana_fitness/qwen_eval_trace.jsonl
```

During assembly, eval status `ok` maps to an accepted eval outcome, `fail` maps
to rejected, and `report` maps to unknown.

The eval can also write analysis-only reflex records:

```bash
mix run lib/qwen_router_prompt_eval.exs -- \
  --runtime-profile mock_tiny \
  --reflex-report \
  --reflex-trace-out ../../tmp/sakana_fitness/qwen_reflex_trace.jsonl
```

This does not change strict snapshot or route-decision pass/fail behavior.

## External Evolution Loop

1. Produce Orchestrator and/or Qwen eval traces.
2. Export deterministic fitness JSONL and its manifest.
3. Feed the dataset to an external Sakana/ES trainer.
4. Write the resulting vector as
   `priv/sakana_trinity/artifacts/trinity_router_es_vector.safetensors`.
5. Generate the adapted bundle with `mix trinity.sakana.export_adapted`.
6. Run import, parity sample, and large-tensor chunk checks.
7. Run the direct Qwen router eval and CUDA HITL gates.

The fitness exporter does not train, mutate, upload, or publish weights.
Candidate generation, selection, optimizer state, and mutation policy belong to
the external trainer. TRINITY resumes ownership when a candidate router vector
enters artifact export and acceptance gates.

Before training or candidate review, run the readiness reports:

```bash
mix trinity.sakana.fitness_inspect \
  --fitness tmp/sakana_fitness/fitness.jsonl \
  --manifest tmp/sakana_fitness/manifest.json \
  --json

mix trinity.sakana.fitness_replay \
  --fitness tmp/sakana_fitness/fitness.jsonl \
  --manifest tmp/sakana_fitness/manifest.json \
  --json

mix trinity.reflex.calibrate \
  --fitness tmp/sakana_fitness/fitness.jsonl \
  --json
```

When external training returns candidate evidence,
`mix trinity.sakana.candidate_eval` produces a proposal report. Candidate eval
is read-only: it validates candidate routes or vector metadata and never writes
accepted artifacts.

## Score Formula V1

The score starts at `0.50`, applies verifier outcome, margin strength, revision,
optional latency/cost, and budget terms, then clamps to `[0.0, 1.0]`.
`profile_floor` computes agent and role ratios against profile defaults and
maps `log2(max(min_ratio, 1.0)) / 4.0` into the margin contribution. Absolute
margin scoring is available only through explicit `--margin-mode absolute` and
`--margin-scale`.

## Output Integrity

Example IDs, dataset digests, and route-hash digests are deterministic. The
manifest records source paths, counts, formula version, margin/content modes,
artifact references, runtime profiles, conflicts, and skipped records. The
assembler never merges a raw trace payload into an example.

Reflex metadata is copied through the same allowlist discipline as route,
dispatch, verifier, budget, artifact, and runtime fields. Older traces without
`reflex_decision` still export.
