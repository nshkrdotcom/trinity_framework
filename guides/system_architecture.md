# System Architecture

`trinity_framework` is the source-of-truth TRINITY runtime with a
deconstructed architecture assembled from the root Mix project.

## Ownership

The root project owns assembly:

- local path deps for all framework packages;
- external runtime deps through `build_support/dependency_sources.config.exs`;
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
  tensor, margin, and profile contracts.
- `core/trinity_sakana_pipeline`: artifact IO, exporter, importer, parity trace,
  stage check, and large tensor chunk logic.
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
