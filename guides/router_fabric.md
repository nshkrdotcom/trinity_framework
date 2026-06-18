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

Downstream applications that need a product-specific adapter should keep that
adapter in their own package or in a dedicated bridge repo. The adapter can map
its local route request into TRINITY messages/options, call one of the
framework entry points above, and translate the returned route decision into
the product receipt shape.

## Standalone And Stack Modes

Standalone TRINITY commands continue to use the local runtime profiles and
operator tasks described in the root README. Stack mode is a consumer concern:
it should depend on the public framework contracts, not on framework internals.

## Local QC

```bash
mix ci
```
