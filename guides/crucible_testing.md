# Trinity Crucible Testing

Use `mix trinity.crucible.inspect`, `mix trinity.crucible.matrix_eval`, `mix trinity.crucible.capabilities`, and `mix trinity.crucible.replay` against checked-in JSONL fixtures before enabling live provider paths. Use `mix trinity.crucible.capture`, `mix trinity.crucible.generation_trace`, `mix trinity.crucible.logit_lens`, and `mix trinity.crucible.patch` with `--fixture tiny_gpt2` for local mech-interp task QC.

Default CI commands must stay fixture-backed. Live model execution remains opt-in through the existing `TRINITY_CRUCIBLE_LIVE` gate and must pass a negotiated `CrucibleTap.TapPlan`.
