# Crucible V5 Final Report

## Summary

- Date: 2026-05-27 HST / 2026-05-28 UTC
- Operator: Codex
- Repos: crucible_signal, crucible_tap, crucible_signal_trace, crucible_policy, crucible_bumblebee, self_hosted_inference_core, trinity_framework, nshkrdotcom docset
- Final implementation status: complete for V5 defined scope, with structured blockers where local libraries or hardware do not expose a capability
- Overall status: QC-green on all target repos; final live model, hosted runtime, Trinity replay, Trinity live, and Trinity matrix gates passed

## Model Matrix Summary

| Model | Backends attempted | Best result | Forward | Generation | Step logits | Hidden states | Attention | Hosted | Trinity |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `hf-internal-testing/tiny-random-gpt2` | Binary, EXLA CPU, Torchx CPU, EXLA CUDA | Binary passed | yes | yes | yes | native blocked; Python captured | native blocked; Python captured | yes | inspect and matrix passed |
| `gpt2` | Binary, EXLA CPU, Torchx CPU, EXLA CUDA | Binary passed | yes | yes | yes | native blocked; Python captured | native blocked; Python captured | yes | inspect and matrix passed |
| `distilgpt2` | Binary, EXLA CPU, Torchx CPU, EXLA CUDA | Binary passed | yes | yes | yes | native blocked | native blocked | yes | inspect and matrix passed |
| `hf-internal-testing/tiny-random-OPTForCausalLM` | Binary, EXLA CPU, Torchx CPU, EXLA CUDA | structured blocker | blocked | blocked | no | blocked | blocked | no | replayed as structured blocker trace |
| `hf-internal-testing/tiny-random-BertModel` | Binary, EXLA CPU, Torchx CPU, EXLA CUDA | structured blocker | blocked by unsupported live surface | no | no | blocked | blocked | no | replayed as structured blocker trace |
| `hf-internal-testing/tiny-random-distilbert` | Binary, EXLA CPU, Torchx CPU, EXLA CUDA | Binary passed | yes | non-causal | no | native blocked | native blocked | yes | inspect and matrix passed |
| `trl-internal-testing/tiny-Qwen3ForCausalLM` | Binary, EXLA CPU, Torchx CPU, EXLA CUDA | Binary passed | yes | yes | yes | native blocked | native blocked | yes | inspect and matrix passed |

## Backend Matrix Summary

| Backend | Models attempted | Passes | Failures | Notes |
| --- | --- | --- | --- | --- |
| Binary | full ladder | M0, M1, M2, M5, M6 | M3 unsupported family, M4 unsupported live surface | portability fallback is the working native backend |
| EXLA CPU | full ladder | 0 | dependency unavailable | recorded as `{:not_installed, :exla}` |
| Torchx CPU | full ladder | 0 | dependency unavailable | recorded as `{:not_installed, :torchx}` |
| EXLA CUDA | full ladder | 0 | dependency unavailable | recorded as `{:not_installed, :exla}` |

## Signal Matrix Summary

| Signal | Captured | Unsupported or blocked | Main blocker |
| --- | --- | --- | --- |
| Input IDs and attention mask | yes | no | none |
| Final logits, top-k, entropy, margin | yes for runnable causal/classification models | unsupported for structured blocker traces | model/load/surface blocker |
| Generation token stream | yes for M0, M1, M2, M6 | M5 non-causal, M3/M4 blocked | model family/surface |
| Generation step logits | yes for M0, M1, M2, M6 through manual loop | no for non-causal/blocker rungs | model family/surface |
| Hidden states | Python provider captured for tiny GPT-2 and GPT-2 | native Bumblebee/Axon path blocked | hidden-state surface not exposed by native stack |
| Attention weights | Python provider captured for tiny GPT-2 and GPT-2 | native Bumblebee/Axon path blocked | attention surface not exposed by native stack |
| Intermediate logits/logit lens | not native | blocked | hidden-state and LM-head hook path unavailable natively |
| Residual/MLP/activation-cache summaries | captured by internals probe where graph candidates existed | active mutation blocked | provider has no active mutation contract |
| Router/MoE telemetry | no | expected unsupported for attempted models | no attempted model exposed MoE router logits |
| KV-cache metadata | no | blocked | native generation path hides cache metadata |

## Generation Summary

| Model | Backend | One-step | Multi-step | Manual loop | Step logits | KV cache |
| --- | --- | --- | --- | --- | --- | --- |
| tiny GPT-2 | Binary | pass | pass | pass | pass | unavailable |
| GPT-2 | Binary | pass | one-step final gate pass; long 8-step earlier timed out at 900s | pass | pass | unavailable |
| distilgpt2 | Binary | pass | pass in final ladder where scoped | pass | pass | unavailable |
| tiny Qwen3 | Binary | pass | pass, including 8-token final gate | pass | pass | unavailable |
| tiny DistilBERT | Binary | non-causal | non-causal | not applicable | not applicable | not applicable |

## Policy Summary

The final Trinity matrix replay evaluated 92 native traces. Selected policies were:

| Policy | Executed count | Main skip reason where skipped |
| --- | --- | --- |
| `final_logits_margin_v0` | 80 | top-k/final logits unavailable on generation-only or blocker traces |
| `final_logits_entropy_v0` | 9 | final logits unavailable on generation-only or blocker traces |
| `spilled_energy_v0` | 1 | generation step logits unavailable |
| `top_k_stability_v0` | 2 | generation step logits unavailable |
| `hidden_state_norm_drift_v0` | 0 native | hidden states unavailable natively |
| `trajectory_drift_v1` | 0 native | intermediate logits unavailable |
| `correction_plan_v0` | dry-run/fallback only | active correction capability unavailable |

## Trinity Summary

| Gate | Status | Artifact |
| --- | --- | --- |
| Inspect replay over every native trace | pass, 92 traces | `tmp/crucible_v5/transcripts/trinity_inspect_all_native_traces_phase17_final.log` |
| Matrix replay over native trace directory | pass, 92 rows | `tmp/crucible_v5/reports/trinity_matrix_eval_native_traces_phase17_final.json` |
| Live inspect M0, M1, M2, M5, M6 | pass | `tmp/crucible_v5/transcripts/trinity_live_inspect_models_phase17_final.log` |
| Live matrix limit 3 with stability repeats | pass | `tmp/crucible_v5/reports/trinity_matrix_live_limit3_phase17_final.json` |
| Live matrix limit 10 | pass | `tmp/crucible_v5/reports/trinity_matrix_live_limit10_phase17_final.json` |
| Live matrix limit 37 | pass | `tmp/crucible_v5/reports/trinity_matrix_live_limit37_phase17_final.json` |

## Python Provider / Snakebridge Decision

- Decision: keep native Bumblebee/Binary as the default local execution substrate, and retain the Python/PyTorch provider for advanced internals that Bumblebee does not expose natively.
- Evidence: Python traces for tiny GPT-2 and GPT-2 captured hidden states, attentions, and generation step logits in Crucible-compatible JSONL; Trinity replay and matrix evaluation passed over those traces.
- Next architecture: use Python/PyTorch as the bridge for hidden-state, attention, and logit-lens research probes until native Bumblebee/Axon exposes equivalent stable hook surfaces.

## Blockers

| Item | Classification | Evidence | Follow-up |
| --- | --- | --- | --- |
| Native hidden states | `blocked_by_bumblebee_api` / `blocked_by_axon_graph` | native signal and internals probes record structured blockers | use Python provider or wait for native hook support |
| Native attention weights | `blocked_by_bumblebee_api` / `blocked_by_axon_graph` | native signal and internals probes record structured blockers | use Python provider or wait for native hook support |
| KV-cache metadata | `blocked_by_generation_pipeline` | generation traces record unavailable cache metadata | add only when Bumblebee exposes cache state |
| EXLA CPU/CUDA | missing dependency | backend ladder recorded `{:not_installed, :exla}` | install EXLA and rerun backend ladder |
| Torchx CPU | missing dependency | backend ladder recorded `{:not_installed, :torchx}` | install Torchx and rerun backend ladder |
| OPT-family tiny model | unsupported native family | model ladder recorded unsupported family | add loader/surface support before claiming pass |
| BERT base live surface | unsupported live surface | model ladder recorded unsupported live surface | add encoder/base trace surface if required |
| Active mutation/residual injection | unsupported provider capability | internals probe fail-closed | require explicit mutation-capable provider contract |

## Artifacts

- Artifact index: `tmp/crucible_v5/ARTIFACT_INDEX.md`
- Transcripts: 120 files under `tmp/crucible_v5/transcripts/`
- Native traces: 150 JSONL files under `tmp/crucible_v5/traces/native/`
- Python traces: 2 JSONL files under `tmp/crucible_v5/traces/python/`
- Capability reports: 147 files under `tmp/crucible_v5/capability_reports/`
- Policy decisions: 336 files under `tmp/crucible_v5/policy_decisions/`
- Route decisions: 336 files under `tmp/crucible_v5/route_decisions/`
- Matrices: model, backend, signal, generation, and internals JSONL files under `tmp/crucible_v5/*_matrix/`

## Claim Audit

- Command: final `rg` audit for stale V4, vertical-slice, and shortcut claim language across target repos, excluding generated dependency/build/tmp directories.
- Result: pass.
- Transcript: `tmp/crucible_v5/transcripts/phase17_claim_audit_final.log`
- Remaining justified hits: none.

## Suppression Audit

- Command: final `rg` audit for Dialyzer/Credo suppression markers across target repos, excluding generated dependency/build/tmp directories.
- Result: pass.
- Transcript: `tmp/crucible_v5/transcripts/phase17_no_suppression_audit_final.log`
- Remaining justified hits: none.

## Final Git State

Implementation/source commits verified before the final artifact-report/docset commits:

| Repo | Commit | Status before final docs |
| --- | --- | --- |
| `crucible_signal` | `cdebf2f` | clean, aligned with origin/main |
| `crucible_tap` | `466f03f` | clean, aligned with origin/main |
| `crucible_signal_trace` | `2376d7e` | clean, aligned with origin/main |
| `crucible_policy` | `d8ac3a5` | clean, aligned with origin/main |
| `crucible_bumblebee` | `a5dc502` | clean, aligned with origin/main |
| `self_hosted_inference_core` | `62276ea` | clean, aligned with origin/main |
| `trinity_framework` | `53014d4` | clean, aligned with origin/main before final artifact-report commit |
| `nshkrdotcom` docset | `66c7d58` | clean, aligned with origin/main before final checklist/report commit |

Push status: all implementation commits were pushed before Phase 17; final artifact-report and docset commits are pushed after this report is written.
