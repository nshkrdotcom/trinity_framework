# System Architecture

`trinity_framework` is the source-of-truth TRINITY runtime with a
deconstructed architecture assembled from the root Mix project.

## Ownership

The root project owns assembly:

- local path deps for all framework packages;
- external runtime deps through portable committed tuples, with optional source
  substitution through the Mix Workspace Ops bootstrap seam;
- root `mix test`, `mix ci`, docs, and Weld packaging;
- all `mix trinity.*` operator commands through `tools/trinity_ops`.

`apps/trinity_single_node` owns the standalone runtime composition. It wires the
contracts, self-hosted inference bridge, provider bridge, trace bridge, Sakana
artifact loading, and execution-plane process runtime into a single-node app.

The next-generation forward-pass substrate is Crucible-owned. Trinity consumes
`crucible_tap` plans, `crucible_signal_trace` refs, and
`crucible_policy` decisions; reusable signal capture and Bumblebee/Nx/Axon
adapter logic stays in the new `crucible_*` packages.

## Package Map

- `core/trinity_contracts`: public `Trinity.*` refs, DTOs, and behaviors.
- `core/trinity_coordinator_core`: orchestrator, budgets, governance,
  role injection, state, thinker, verifier, and route derivation.
- `core/trinity_sakana_contracts`: Sakana manifest, route hash input, selected
  tensor, margin/profile, fitness example/manifest, and deterministic score
  contracts.
- `core/trinity_sakana_pipeline`: streaming trace reader, allowlist fitness
  assembler, JSONL/manifest writer, fitness exporter, artifact IO, adapted
  exporter/importer, parity trace, stage checks, and large tensor chunk logic.
- `bridges/trinity_bridge_self_hosted_inference`: model runtime adapter over
  `self_hosted_inference_core` and `self_hosted_inference_bumblebee`.
- `bridges/trinity_bridge_inference`: provider/agent caller bridge over
  `:inference`.
- `bridges/trinity_bridge_trace`: AITrace-shaped JSONL, hash, context, and
  redaction bridge.
- `tools/trinity_ops`: framework-owned implementation of operator tasks.
- `examples/qwen_router_prompt_eval`: 37-case prompt routing eval.
- `examples/crucible_route`: minimal Crucible route example.
- `../../North-Shore-AI/crucible_signal`: forward-pass signal ontology.
- `../../North-Shore-AI/crucible_tap`: tap-plan contracts and capability
  negotiation.
- `../../North-Shore-AI/crucible_signal_trace`: bounded forward-trace records.
- `../../North-Shore-AI/crucible_bumblebee`: Bumblebee/Nx/Axon adapter and
  first working forward-runner slice.
- `../../North-Shore-AI/crucible_policy`: routing, gating, uncertainty, and
  steering decisions over signal traces.

## Dependency Direction

The framework may depend on reusable runtime libraries such as Crucible,
self-hosted inference, `:inference`, AITrace, and execution plane libraries.
It must not depend on product integration packages. Those integrate from their
side through public TRINITY contracts and generic projection references.

## Runtime Flow

1. Build a `CrucibleTap.TapPlan` from `Trinity.Crucible.RequestContext`.
2. Run the configured Crucible-capable model runtime.
3. Produce a bounded `%Crucible.ForwardTrace{}`.
4. Produce a `CruciblePolicy.RouteDecision`.
5. Adapt that decision into `Trinity.Coordinator.RouteDecision` through
   `Trinity.Crucible.DecisionAdapter`.
6. Dispatch through the provider or self-hosted runtime bridge.
7. Emit trace and decision refs through the trace bridge.

## Fitness Evidence Flow

1. `Trinity.Ops.OrchestratorRunner` loads the existing single-node route runtime
   and calls `Trinity.Coordinator.Orchestrator.run_loop/2`.
2. The Orchestrator owns routing, provider dispatch, verifier transitions,
   revision counters, budget checks, and lifecycle trace events.
3. The JSONL trace bridge persists route, dispatch, verifier, budget, and
   terminal events without raw provider response bodies.
4. `Trinity.Sakana.TraceFitnessReader` streams records without atomizing input
   keys.
5. `TraceFitnessAssembler` joins records by run, turn, route hash, and dispatch
   ref, copying only explicitly allowed fields.
6. `FitnessScore` applies the schema-versioned deterministic formula and
   `FitnessJsonlWriter` writes examples plus a digest-bearing manifest.
7. An external ES trainer consumes the dataset and returns a reviewed router
   vector. Existing adapted export, parity, eval, and CUDA gates validate it.

Verifier `revision_count` is post-decision cumulative state. This definition
keeps each route example self-contained and attributes a revision penalty to
the verifier decision that caused it.
