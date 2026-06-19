<p align="center">
  <img src="assets/trinity_framework.svg" alt="TRINITY Framework" width="220" />
</p>

<p align="center">
  <a href="https://github.com/nshkrdotcom/trinity_framework"><img alt="GitHub" src="https://img.shields.io/badge/github-nshkrdotcom%2Ftrinity__framework-24292f?logo=github" /></a>
  <a href="https://huggingface.co/datasets/nshkrdotcom/trinity-coordinator-adapted-qwen3-0.6b"><img alt="HuggingFace Dataset" src="https://img.shields.io/badge/huggingface-adapted--qwen3--0.6b-ffd21e" /></a>
  <img alt="Elixir" src="https://img.shields.io/badge/elixir-1.18%2B-4b275f?logo=elixir" />
  <img alt="License" src="https://img.shields.io/badge/license-MIT-0f766e" />
</p>

# TRINITY Framework

`trinity_framework` is the new source-of-truth TRINITY repository. The root
Mix project is the assembled framework distribution: it wires the
deconstructed contracts, coordinator behavior, Sakana artifact pipeline, bridge
packages, single-node runtime, operator command surface, and eval example into
one standalone checkout.

The completion target for this repo is exact and testable: all framework
runtime, operator, bridge, eval, and Crucible assembly behavior is owned here
through the deconstructed package architecture. There is no alternate old route
mode in this repository.

## Status

The root project owns the operator-facing assembly:

- `core/trinity_contracts` defines the reusable router, role, provider,
  verifier, trace, session, artifact, and coordination contracts.
- `core/trinity_coordinator_core` owns the coordinator behavior extracted from
  the former monolith.
- `core/trinity_sakana_contracts` and `core/trinity_sakana_pipeline` own the
  adapted-Qwen/Sakana artifact contracts, trace-derived fitness schema and
  scoring, deterministic dataset export, artifact export/import, and parity
  surfaces.
- `bridges/trinity_bridge_inference`,
  `bridges/trinity_bridge_self_hosted_inference`, and
  `bridges/trinity_bridge_trace` connect TRINITY to inference and trace
  packages without moving ownership into the root facade.
- `apps/trinity_single_node` is the standalone runtime app.
- `tools/trinity_ops` owns every `mix trinity.*` operator command.
- `examples/qwen_router_prompt_eval` owns the 37-case Qwen router prompt eval.
- `examples/crucible_route` shows the reusable Crucible route path.

This repo is also the integration point for the nshkr stack. It must be able to
run standalone and sit inside larger product, governance, execution, and testing
flows through explicit package contracts and governed provider boundaries.

## Quickstart

```bash
git clone https://github.com/nshkrdotcom/trinity_framework
cd trinity_framework
mix deps.get
mix test
mix ci
```

`mix test` must run root aggregate tests. If it reports that there are no tests
to run, the root project is not complete.

For CUDA routes:

```bash
XLA_TARGET=cuda12 mix trinity.env.check
```

`XLA_TARGET=cuda12` is the supported CUDA target. CPU/mock documentation and
smoke work can use the `mock_tiny` runtime profile where a command exposes
`--runtime-profile`.

## Fetch The Adapted Bundle

The generated adapted-Qwen3 safetensors bundle is not committed to git. The
pin file is committed at `priv/sakana_trinity/artifact_pin.json`, and the
default published dataset remains:

```text
nshkrdotcom/trinity-coordinator-adapted-qwen3-0.6b
```

Fetch and verify the bundle:

```bash
mix trinity.artifact.fetch
```

Offline cache-only fetch:

```bash
HF_HUB_OFFLINE=1 mix trinity.artifact.fetch --offline
```

Custom destination or pin:

```bash
mix trinity.artifact.fetch --dest priv/sakana_trinity/my_bundle
mix trinity.artifact.fetch --pin priv/forks/my_pin.json
```

The default runtime bundle lands at:

```text
priv/sakana_trinity/adapted_qwen3_0_6b_layer26
```

## Run The Runtime

Safe mock-provider smoke checks:

```bash
mix trinity.gates
mix trinity.route.demo \
  --mock-provider \
  --runtime-profile mock_tiny \
  --max-turns 1 \
  --trace-out tmp/trinity_route_demo.jsonl

mix trinity.hitl.mock_loop \
  --runtime-profile mock_tiny \
  --max-turns 1 \
  --trace-out tmp/trinity_mock_loop.jsonl

mix trinity.crucible.inspect --runtime-profile mock_tiny
mix trinity.crucible.matrix_eval --runtime-profile mock_tiny
```

CUDA/adapted bundle checks:

```bash
XLA_TARGET=cuda12 mix trinity.hitl.gpu
XLA_TARGET=cuda12 mix trinity.hitl.vector
XLA_TARGET=cuda12 mix trinity.hitl.head_route
XLA_TARGET=cuda12 mix trinity.hitl.base_qwen
XLA_TARGET=cuda12 mix trinity.hitl.adapted
```

Gated live provider route demo:

```bash
XLA_TARGET=cuda12 mix trinity.route.demo \
  --allow-live \
  --provider-pool governed \
  --governed-provider openai \
  --governed-model gpt-4.1-mini \
  --governed-api-key "$OPENAI_API_KEY" \
  --trace-out tmp/trinity_live_route_demo.jsonl
```

Live provider commands must stay opt-in. The default path should not spend
provider budget.

## Run The Eval

The main route-decision proof is the 37-case Qwen router prompt eval:

```bash
cd examples/qwen_router_prompt_eval
XLA_TARGET=cuda12 mix run lib/qwen_router_prompt_eval.exs -- \
  --snapshot fixtures/qwen_router_prompt_eval_logits.json \
  --determinism-runs 2
```

Useful eval variants:

```bash
mix run lib/qwen_router_prompt_eval.exs -- --list-cases

XLA_TARGET=cuda12 mix run lib/qwen_router_prompt_eval.exs -- \
  --case planner.basic \
  --snapshot fixtures/qwen_router_prompt_eval_logits.json

XLA_TARGET=cuda12 mix run lib/qwen_router_prompt_eval.exs -- \
  --snapshot-out tmp/qwen_router_prompt_eval_logits.json \
  --determinism-runs 2
```

The eval asserts route decisions, margins, stable transcript fields, and
determinism.

The root eval wrapper runs the Crucible route-decision path. With no profile it
defaults to the mock contract lane:

```bash
mix trinity.eval qwen_router_prompt_eval
```

That command prints `Runtime profile: mock_tiny`, `Qwen runtime: not loaded`,
and `Contract-path eval only`. It proves the Crucible contract path, not the
adapted Qwen router.

Use the CUDA profile when the wrapper should load the self-hosted Qwen/Sakana
route runtime:

```bash
XLA_TARGET=cuda12 mix trinity.eval qwen_router_prompt_eval \
  --runtime-profile cuda_exla
```

The strict snapshot fixture remains owned by the direct example eval command.
Treat the wrapper report as route/contract acceptance, and the direct example
snapshot as a separate, provenance-sensitive logits fixture gate.

## Export Sakana Fitness Evidence

Produce fitness-bearing traces through the real coordinator Orchestrator, then
export an allowlisted dataset for an external ES trainer:

```bash
mix trinity.orchestrator.demo \
  --runtime-profile mock_tiny \
  --mock-provider \
  --max-turns 3 \
  --trace-out tmp/orchestrator_demo/trace.jsonl

mix trinity.sakana.fitness_export \
  --trace tmp/orchestrator_demo/trace.jsonl \
  --out tmp/sakana_fitness/fitness.jsonl \
  --manifest-out tmp/sakana_fitness/manifest.json \
  --json
```

The producer calls `Trinity.Coordinator.Orchestrator.run_loop/2` through the
existing single-node model runtime and provider bridge. It does not use the
legacy smoke loop or duplicate routing, verifier, revision, or budget logic.
Mock mode is deterministic and needs no network, CUDA artifact, or provider
credential; live provider execution requires explicit `--allow-live`.

Router confidence is operational in the Orchestrator. High-confidence routes
record `direct_dispatch` and dispatch immediately, medium-confidence routes
record `normal_dispatch` and keep the current behavior, and low-confidence
routes record `thinker_then_verifier` and force Thinker before Verifier. Disable
this only for legacy comparisons with `--no-reflex`; see
[Router Reflex](docs/router_reflex.md).

Each trace contains route, provider dispatch, verifier, budget, and terminal
run events, including `reflex_decision` when reflex is enabled. A verifier
`revision_count` is cumulative after applying the current verifier decision, so
a first `revise` event carries `1` and receives the revision penalty on that
route. Accepted decisions do not increment it.

The exporter streams string-key JSONL and copies a fixed field allowlist. Hash
content mode is the default; `--content full` is the only mode that can carry
deliberately captured input content. API keys, authorization, headers, endpoint
authentication, and raw provider bodies are never fitness fields. Example IDs,
route-hash digests, dataset digests, and score-v1 labels are deterministic.

The Qwen prompt eval is also a fitness evidence source:

```bash
cd examples/qwen_router_prompt_eval
mix run lib/qwen_router_prompt_eval.exs -- \
  --runtime-profile mock_tiny \
  --trace-out ../../tmp/sakana_fitness/qwen_eval_trace.jsonl
```

This feature scores and exports evidence only. External ES owns candidate
generation, optimization, and weight mutation; the framework resumes ownership
at router-vector validation, adapted artifact export, parity, eval, and CUDA
acceptance. See [Sakana Fitness Export](docs/sakana_fitness_export.md).

Reflex classification can also be reported during the Qwen prompt eval without
changing strict eval semantics:

```bash
cd examples/qwen_router_prompt_eval
mix run lib/qwen_router_prompt_eval.exs -- \
  --runtime-profile mock_tiny \
  --reflex-report \
  --reflex-trace-out ../../tmp/sakana_fitness/qwen_reflex_trace.jsonl
```

## Generate Safetensors

The adapted bundle can be regenerated from the Sakana vector and Qwen base
model:

```bash
XLA_TARGET=cuda12 mix trinity.sakana.export_adapted \
  --out priv/sakana_trinity/adapted_qwen3_0_6b_layer26 \
  --source-vector priv/sakana_trinity/artifacts/trinity_router_es_vector.safetensors \
  --force
```

Dry-run the export plan without writing the bundle:

```bash
mix trinity.sakana.export_adapted --dry-run --json
```

Run one tensor slice while debugging:

```bash
XLA_TARGET=cuda12 mix trinity.sakana.export_adapted \
  --out tmp/adapted_qwen3_probe \
  --only-index 1 \
  --force
```

Python semantic imports and parity checks:

```bash
mix trinity.sakana.import_python \
  --source-dir priv/sakana_trinity/python_export \
  --manifest priv/sakana_trinity/reference/sakana_python_reference_manifest.json \
  --out priv/sakana_trinity/adapted_qwen3_0_6b_layer26 \
  --json

mix trinity.sakana.parity_sample \
  --python-report priv/sakana_trinity/reference/sakana_python_reference_manifest.json \
  --semantic-only \
  --no-cuda \
  --out tmp/sakana_parity_sample.json

mix trinity.sakana.large_tensor_chunks \
  --python-report priv/sakana_trinity/reference/sakana_python_reference_manifest.json \
  --chunk-rows 2048 \
  --no-cuda \
  --out tmp/sakana_large_tensor_chunks.json
```

## Upload To HuggingFace

Publishing is intentionally not hidden behind an accidental default command.
Use the `hf_hub` library in an authenticated IEx session after generating and
reviewing the bundle:

```elixir
repo_id = "nshkrdotcom/trinity-coordinator-adapted-qwen3-0.6b"
source_dir = "priv/sakana_trinity/adapted_qwen3_0_6b_layer26"
token = caller_owned_huggingface_token

{:ok, _repo} =
  HfHub.Repo.create(repo_id,
    repo_type: :dataset,
    exist_ok: true,
    token: token
  )

{:ok, commit} =
  HfHub.Commit.upload_folder(
    source_dir,
    repo_id,
    repo_type: :dataset,
    token: token,
    commit_message: "Publish adapted Qwen3 bundle",
    ignore_patterns: ["*.log.jsonl", "*.tmp", ".DS_Store"]
  )

commit
```

After upload, verify the remote tree against `manifest.json`, regenerate or
update `priv/sakana_trinity/artifact_pin.json`, and tag the remote revision that
fresh clones should consume.

## Command Reference

```text
mix trinity.artifact.fetch             # Download and SHA-verify the adapted bundle
mix trinity.demo                       # Compatibility wrapper for the route demo
mix trinity.env.check                  # Validate build/runtime environment
mix trinity.gates                      # Run the TRINITY quality gate matrix
mix trinity.hitl.adapted               # Adapted-Qwen coordinator route check
mix trinity.hitl.base_qwen             # Base Qwen hidden-state check
mix trinity.hitl.gpu                   # GPU/EXLA CUDA visibility check
mix trinity.hitl.head_route            # Hidden-state to Sakana-head route check
mix trinity.hitl.mock_loop             # Mock orchestrator loop check
mix trinity.hitl.vector                # Sakana router-vector split check
mix trinity.orchestrator.demo          # Produce Orchestrator/reflex fitness traces
mix trinity.parity.check               # Python/Elixir parity comparator wrapper
mix trinity.route.demo                 # Gated route demo
mix trinity.sakana.export_adapted      # Export adapted Qwen tensors and router head
mix trinity.sakana.fitness_export      # Export deterministic route fitness JSONL
mix trinity.sakana.import_python       # Import Python semantic Sakana artifacts
mix trinity.sakana.large_tensor_chunks # Replay large tensor stages in chunks
mix trinity.sakana.parity_sample       # Emit SVD/SVF parity diagnostics
mix trinity.sakana.router_trace        # Emit fixed-transcript router trace
```

Run `mix help --search trinity` for the authoritative local task list.

## Quality Gates

The final root acceptance target is:

```bash
mix test
mix ci
mix help --search trinity
mix trinity.gates
mix trinity.artifact.fetch
XLA_TARGET=cuda12 mix trinity.hitl.gpu
XLA_TARGET=cuda12 mix trinity.hitl.vector
XLA_TARGET=cuda12 mix trinity.hitl.head_route
XLA_TARGET=cuda12 mix trinity.hitl.base_qwen
XLA_TARGET=cuda12 mix trinity.hitl.adapted
```

`mix ci` expands to dependency fetch, formatting, warning-as-error compile,
tests, Credo strict, Dialyzer, docs generation, and Weld projection checks.
No framework warnings, test failures, Credo issues, or Dialyzer issues are
acceptable for sign-off.

## Guides

- [Onboarding](guides/onboarding.md)
- [Current Direction](guides/current_direction.md)
- [System Architecture](guides/system_architecture.md)
- [Service Buildout](guides/service_buildout.md)
- [Operations And QC](guides/operations_qc.md)
- [Artifact Distribution](guides/artifact_distribution.md)
- [Artifacts And Export](guides/artifacts_and_export.md)
- [Sakana Fitness Export](docs/sakana_fitness_export.md)
- [Router Reflex](docs/router_reflex.md)
- [Runtime Profiles](guides/runtime_profiles.md)
- [Evals](guides/evals.md)
- [Python Parity Reconstruction](guides/python_parity_reconstruction.md)
- [Python Torch Trace Provider](guides/python_torch_trace_provider.md)
- [Stage Checks And Tolerances](guides/stage_checks_and_tolerances.md)
- [SVD Generation Runbook](guides/svd_generation_runbook.md)
- [Provider Service Hardening](guides/provider_service_hardening.md)
- [Troubleshooting](guides/troubleshooting.md)
- [Production Runbook](docs/production_runbook.md)
- [Provider Smoke Tests](docs/provider_smoke_tests.md)
- [Sakana Adapted Artifact Plan](docs/sakana_adapted_artifact_plan.md)
- [Trace Persistence](docs/trace_persistence.md)

## Repository Layout

```text
assets/                         Logos and static docs assets
bridges/                        Integration bridge packages
core/                           Contracts, coordinator core, Sakana pipeline
apps/trinity_single_node/       Standalone runtime application
tools/trinity_ops/              mix trinity.* operator commands
examples/qwen_router_prompt_eval/ 37-case router prompt eval
priv/sakana_trinity/            Artifact pins, scripts, references, local bundle
guides/                         Operator and architecture documentation
docs/                           Reference notes and production runbooks
test/                           Root aggregate and drift tests
```

## Requirements

- Elixir/Erlang from `.tool-versions`.
- CUDA-capable Linux host for CUDA acceptance and adapted-Qwen runtime checks.
- HuggingFace network access for first-time `mix trinity.artifact.fetch`.
- `HF_TOKEN` or equivalent HuggingFace auth only when publishing bundles.
- Python, PyTorch, Transformers, NumPy, and safetensors only for Python parity
  reconstruction and original Sakana script workflows.

## References

[1] Jinglue Xu, Qi Sun, Peter Schwendeman, Stefan Nielsen, Edoardo
Cetin, and Yujin Tang. *TRINITY: An Evolved LLM Coordinator*.
arXiv:2512.04695, 2026. <https://arxiv.org/abs/2512.04695>

## License

MIT.

## V5 Status

Status: `trinity-v5-live-replay-matrix-python-trace-passing`.

The Crucible operator tasks support V5 artifact-backed trace replay, native
hosted runtime live inspect, live matrix eval, role-boundary stability reports,
policy/route decision artifact emission, and external Python/PyTorch trace
production for model internals that Bumblebee does not expose:

```bash
mix trinity.crucible.inspect --trace tmp/crucible_v5/traces/native/model_forward_live.trace.jsonl --artifact-root tmp/crucible_v5
mix trinity.crucible.matrix_eval --trace tmp/crucible_v5/traces/native --artifact-root tmp/crucible_v5
TRINITY_CRUCIBLE_LIVE=true mix trinity.crucible.inspect --live --model-id gpt2 --backend binary --artifact-root tmp/crucible_v5 --prompt "Hi"
TRINITY_CRUCIBLE_LIVE=true mix trinity.crucible.matrix_eval --live --limit 37 --backend binary --artifact-root tmp/crucible_v5
python3 tools/python/crucible_torch_trace.py --model-id gpt2 --artifact-root tmp/crucible_v5 --trace-name python_torch_gpt2_phase15
mix trinity.crucible.inspect --trace tmp/crucible_v5/traces/python/python_torch_gpt2_phase15.trace.jsonl --artifact-root tmp/crucible_v5
```

See [Trinity Live Inspect](guides/trinity_live_inspect.md) and
[Python Torch Trace Provider](guides/python_torch_trace_provider.md).
