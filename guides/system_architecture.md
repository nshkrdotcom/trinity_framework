# System Architecture

`trinity_framework` replaces the old monolithic `trinity_coordinator` runtime
with a deconstructed architecture that is still assembled from the root Mix
project.

## Ownership

The root project owns assembly:

- local path deps for all framework packages;
- external runtime deps through `build_support/dependency_sources.config.exs`;
- root `mix test`, `mix ci`, docs, and Weld packaging;
- all `mix trinity.*` operator commands through `tools/trinity_ops`.

`apps/trinity_single_node` owns the standalone runtime composition. It wires the
contracts, self-hosted inference bridge, provider bridge, trace bridge, Sakana
artifact loading, and execution-plane process runtime into a single-node app.

`trinity_coordinator` owns no new runtime implementation. It remains a v2 shim
for one release window so old imports and `mix trinity.*` commands keep working.

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
- `bridges/trinity_bridge_trace`: AITrace-compatible JSONL, hash, context, and
  redaction bridge.
- `tools/trinity_ops`: framework-owned implementation of old operator tasks.
- `examples/qwen_router_prompt_eval`: 37-case prompt routing eval.

## Dependency Direction

The framework may depend on reusable runtime libraries such as Crucible,
self-hosted inference, `:inference`, AITrace, and execution plane libraries.
It must not depend on product integration packages. Those integrate from their
side through public TRINITY contracts and generic projection references.

## Runtime Flow

1. Fetch or generate a Sakana-adapted Qwen artifact bundle.
2. Load a runtime profile in `Trinity.SingleNode`.
3. Extract hidden state from Qwen layer 26.
4. Apply the Sakana head to select agent and role.
5. Build a `Trinity.Coordinator.RouteDecision`.
6. Dispatch through the provider or self-hosted runtime bridge.
7. Emit trace events through the trace bridge.
