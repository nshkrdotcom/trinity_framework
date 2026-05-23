# Troubleshooting

## Root `mix test` Says There Are No Tests

This is a release blocker. The root aggregate must have tests. Run:

```bash
mix test
```

Expected output includes root tests and `0 failures`.

## Artifact Fetch Checksum Mismatch

Clear the HuggingFace dataset cache and retry:

```bash
rm -rf ~/.cache/huggingface/hub/datasets--nshkrdotcom--trinity-coordinator-adapted-qwen3-0.6b
mix trinity.artifact.fetch
```

## Offline Fetch Fails

You ran offline mode before the cache was warm:

```bash
HF_HUB_OFFLINE=1 mix trinity.artifact.fetch --offline
```

Run one online fetch first, then retry offline.

## CUDA Not Visible

Run:

```bash
mix trinity.hitl.gpu
```

Check `nvcc`, driver visibility, and `XLA_TARGET`. For CUDA eval/export use:

```bash
XLA_TARGET=cuda12
```

## Eval Fails

Re-run with native logs:

```bash
cd examples/qwen_router_prompt_eval
XLA_TARGET=cuda12 mix run lib/qwen_router_prompt_eval.exs -- \
  --debug-native-logs \
  --snapshot fixtures/qwen_router_prompt_eval_logits.json
```

Check:

- artifact bundle exists;
- runtime profile is correct;
- snapshot matches the intended profile;
- route margins are not below profile defaults.

## Export Fails

Start with dry run:

```bash
mix trinity.sakana.export_adapted --dry-run --json
```

Then run a single tensor:

```bash
XLA_TARGET=cuda12 mix trinity.sakana.export_adapted --only-index 1 --force
```

## Coordinator Paths Appear In Framework

Search:

```bash
rg -n "/home/home/p/g/n/trinity_coordinator|../trinity_coordinator|test/trinity_coordinator" \
  --glob '!deps/**' --glob '!_build/**' --glob '!dist/**' --glob '!tmp/**'
```

Hard-coded implementation paths back to the old coordinator are blockers.

