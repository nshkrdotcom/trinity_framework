# Current Direction

`trinity_framework` is the source-of-truth repository for the deconstructed
TRINITY stack. Runtime behavior, operator commands, examples, and Crucible
assembly are owned here through explicit package boundaries.

## Active Priorities

1. Keep reusable packages small and explicit.
2. Keep TRINITY product naming in framework packages, not in Crucible packages.
3. Maintain the complete operator command surface from the framework root.
4. Keep artifact, eval, parity, and docs gates runnable from a fresh checkout.
5. Publish deconstructed packages through governed dependency manifests.
6. Expose Crucible as the reusable route path without hard-wiring it to Qwen.

## Done Means

- `mix test` runs root aggregate tests.
- `mix ci` is clean.
- `mix help --search trinity` lists all 20 operator tasks.
- The 37-case Qwen router eval is documented and runnable.
- `mix trinity.eval qwen_router_prompt_eval` passes strict
  route-decision acceptance.
- CUDA/adapted checks are documented and run on capable hosts.
