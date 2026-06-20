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
7. Close the route-evidence loop with Orchestrator-backed, allowlisted Sakana
   fitness datasets for external ES training.
8. Make router confidence operational through the Orchestrator reflex policy:
   high margins dispatch directly, medium margins preserve normal behavior,
   and low margins force Thinker before Verifier.

## Evolution Boundary

The framework owns evidence production, deterministic fitness assembly and
scoring, router-vector artifact import/export, parity, and runtime acceptance.
Candidate generation, optimization, and weight mutation stay in an external ES
trainer. This boundary keeps training dependencies and mutation policy out of
the reusable runtime while preserving a schema-versioned handoff in both
directions.

## Done Means

- `mix test` runs root aggregate tests.
- `mix ci` is clean.
- `mix help --search trinity` lists the complete operator task surface.
- The 37-case Qwen router eval is documented and runnable.
- `mix trinity.eval qwen_router_prompt_eval` passes strict
  route-decision acceptance.
- CUDA/adapted checks are documented and run on capable hosts.
- `mix trinity.orchestrator.demo` produces verifier/budget-bearing traces and
  `mix trinity.sakana.fitness_export` converts them into deterministic datasets.
- Route confidence appears as `reflex_decision` evidence, and low-confidence
  Orchestrator runs exercise Thinker-to-Verifier escalation without creating a
  separate agent loop.
- Verifier revision counts describe state after the current decision, and
  exported fitness examples contain only allowlisted trace fields.
- External training can return a reviewed router vector to the existing
  adapted-export, parity, eval, and CUDA acceptance path.
- The adaptation readiness loop now adds dataset inspection, score replay,
  reflex calibration, and non-mutating candidate proposal reports before any
  candidate vector enters artifact export gates.
