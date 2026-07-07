# Trinity Crucible Mech-Interp Tasks

The local mech-interp tasks run a deterministic tiny GPT-2 model through
Bumblebee/Axon and then use CrucibleBumblebee plus CrucibleMechInterp primitives
for capture, generation telemetry, logit lens, and activation patching. They do
not download model weights and do not use placeholder providers.

## Tiny GPT-2 Walkthrough

```bash
mix trinity.crucible.capture \
  --fixture tiny_gpt2 \
  --input-ids 1,2,3 \
  --artifact-root tmp/crucible_mechinterp

mix trinity.crucible.generation_trace \
  --fixture tiny_gpt2 \
  --input-ids 1,2,3 \
  --max-new-tokens 2 \
  --artifact-root tmp/crucible_mechinterp

mix trinity.crucible.logit_lens \
  --fixture tiny_gpt2 \
  --input-ids 1,2,3 \
  --top-k 5 \
  --artifact-root tmp/crucible_mechinterp

mix trinity.crucible.patch \
  --fixture tiny_gpt2 \
  --clean-input-ids 1,2,3 \
  --corrupted-input-ids 1,2,4 \
  --patch-activation blocks.0.hook_resid_pre \
  --patch-pos 1 \
  --artifact-root tmp/crucible_mechinterp
```

Expected artifacts:

- `reports/capture_report.json` summarizes emitted activation names, capture
  groups, and the compiled tap-plan options.
- `traces/capture_trace.json` contains bounded signal summaries for final
  logits, residual streams, Q/K/V, attention pattern/scores/Z, MLP activations,
  and norm telemetry.
- `reports/generation_trace_report.json` includes generated token ids,
  KV-cache offsets, and the generation-step logits activation cache summary.
- `reports/logit_lens_report.json` includes accumulated-residual labels and
  per-label top-k logits from the real unembedding projection.
- `reports/patch_report.json` records clean/corrupted/patched summaries and a
  selected-position equality check after cache patching.

## Qwen3 Local Walkthrough

Qwen3 native internals are exposed through the EMLX Qwen3 bridge in
`/home/home/p/g/North-Shore-AI/crucible_bumblebee` and the pinned EMLX fork in
`/home/home/p/g/elixir-nx/emlx` branch `phase-9-qwen3-trace`. Registry pins can
consume `CrucibleBumblebee.EMLXQwen3.provider_compatibility/1` for supported
activation names, capture groups, KV-cache generation telemetry, and residual
intervention support.

The fork branch is kept in sync with `elixir-nx/emlx` main (merged through
the fused kv_cache+sdpa PR, elixir-nx/emlx#124) for native compiler and NIF
improvements, while keeping our own instrumented `EMLXAxon.Qwen3.{Model,
Attention,Generate}` rather than upstream's independent, non-instrumented
dense-generation path shipped under the same module names — see
`crucible_bumblebee`'s `guides/emlx_qwen3.md` for the current pinned ref and
rationale.

The Trinity local task defaults stay on `tiny_gpt2` because they must run in CI
without external model weights. A Qwen3 operator run should use the EMLX bridge
once model weights are locally available, then feed the emitted trace into:

```bash
mix trinity.crucible.trace_replay \
  --trace tmp/crucible_v5/traces/native/qwen3.trace.jsonl \
  --artifact-root tmp/crucible_v5
```

## QC

Run the focused task tests before committing Trinity changes:

```bash
mix test test/trinity/ops/native_tasks_test.exs
mix test test/trinity/ops/command_spec_test.exs
```

Run at least one end-to-end walkthrough command locally:

```bash
mix trinity.crucible.capture --fixture tiny_gpt2 --artifact-root tmp/crucible_mechinterp
```
