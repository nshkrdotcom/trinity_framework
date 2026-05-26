# Router Fabric Integration

TRINITY owns reusable route planning and coordination behavior. In the NSHKR
stack it plugs into Mezzanine through a concrete adapter rather than making
Mezzanine depend on TRINITY internals.

## Mezzanine Adapter

`Trinity.MezzanineRouterAdapter` lives in
`core/trinity_coordinator_core` and implements
`Mezzanine.AIExecution.RouterAdapter`.

The adapter accepts Mezzanine route requests and returns route decision refs,
route plan refs, candidate model class refs, trace refs, and bounded failure
reason codes. It does not execute model calls, admit workflows, grant
authority, or project product state.

Model classes and model profiles are distinct. The adapter resolves
`model_class_ref` values through `model_class_profile_map` supplied by the
request, adapter options, or deterministic defaults. The selected output is a
`model-profile://...` ref; unmapped classes are rejected with
`trinity.route.model_class_unmapped.v1`.

## Standalone And Stack Modes

Standalone TRINITY commands continue to use the local runtime profiles and
operator tasks described in the root README. Stack mode binds through
Mezzanine's adapter contract and is proven by StackLab router fabric canaries.

## Local QC

```bash
mix ci
```
