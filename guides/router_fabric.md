# Router Fabric Integration

TRINITY owns reusable route planning and coordination behavior. Product
systems should bind to it through explicit framework contracts instead of
placing product adapters in this repo.

## Framework Contract

The supported integration points are:

- `Trinity.Router.route/2` for pure coordinator contract routing.
- `Trinity.SingleNode.route/2` for route-logits runtime routing.
- `Trinity.SingleNode.dispatch/3` for governed provider dispatch after a route.
- `Trinity.Coordinator.RouteDecision` and `TraceEvent` for downstream receipts.
- `Trinity.Coordinator.ReflexPolicy.evaluate/2` for deterministic confidence
  classification when an integration needs the same high/medium/low policy as
  the Orchestrator.

Downstream applications that need a product-specific adapter should keep that
adapter in their own package or in a dedicated bridge repo. The adapter can map
its local route request into TRINITY messages/options, call one of the
framework entry points above, and translate the returned route decision into
the product receipt shape.

## Standalone And Stack Modes

Standalone TRINITY commands continue to use the local runtime profiles and
operator tasks described in the root README. Stack mode is a consumer concern:
it should depend on the public framework contracts, not on framework internals.

## Confidence Reflex

The coordinator Orchestrator owns the operational reflex path. High-confidence
routes dispatch the selected role directly, medium-confidence routes preserve
normal behavior, and low-confidence routes force Thinker before Verifier. This
keeps system-1/system-2 routing inside the reusable coordinator loop instead of
duplicating it in product adapters.

Reflex role overrides preserve the router-selected agent slot. The policy can
change Worker into Thinker or Verifier for the execution path, but it does not
silently remap `selected_agent_id`; provider placement remains a provider-pool
or agent-slot mapping concern.

Downstream consumers should treat `reflex_decision` trace events as execution
evidence. They should not infer reflex behavior by re-reading raw prompts or
provider payloads, and they should not create a separate agent loop to mimic
the Orchestrator.

## Local QC

```bash
mix ci
```
