# Current Direction

`trinity_framework` is the source-of-truth repository for the deconstructed
TRINITY stack. The old coordinator monolith is a compatibility shim, not the
owner of new behavior.

## Active Priorities

1. Keep reusable packages small and explicit.
2. Keep TRINITY product naming in framework packages, not in Crucible packages.
3. Maintain the full old operator command surface from the framework root.
4. Keep artifact, eval, parity, and docs gates runnable from a fresh checkout.
5. Publish deconstructed packages through governed dependency manifests.

## Done Means

- `mix test` runs root aggregate tests.
- `mix ci` is clean.
- `mix help --search trinity` lists all 17 operator tasks.
- The 37-case Qwen router eval is documented and runnable.
- CUDA/adapted checks are documented and run on capable hosts.
