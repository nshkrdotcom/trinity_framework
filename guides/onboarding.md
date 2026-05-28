# Onboarding

This repo is the new TRINITY source of truth. The root Mix project assembles the
deconstructed framework packages, bridge packages, operator tasks, the
single-node app, and the prompt-eval example. The old `trinity_coordinator` repo
is only a deprecated compatibility shim.

## Prerequisites

- Elixir and Erlang from `.tool-versions`.
- CUDA-capable Linux host for CUDA routes, or a supported non-CUDA runtime
  profile for smoke/documentation work.
- Internet access for first-time HuggingFace downloads.
- Optional `HF_TOKEN` only for publisher uploads. Runtime library code must not
  read arbitrary environment variables.

## Fresh Clone

```bash
git clone https://github.com/nshkrdotcom/trinity_framework
cd trinity_framework
mix deps.get
mix test
mix ci
```

`mix test` must run root aggregate tests. If it says there are no tests to run,
the repo is not ready.

## Artifact Setup

The generated adapted bundle is not committed. Fetch it with:

```bash
mix trinity.artifact.fetch
```

The default destination is:

```text
priv/sakana_trinity/adapted_qwen3_0_6b_layer26
```

Offline cache-only fetch:

```bash
HF_HUB_OFFLINE=1 mix trinity.artifact.fetch --offline
```

## First Runtime Checks

```bash
mix trinity.env.check
mix trinity.gates
mix trinity.route.demo --mock-provider --runtime-profile mock_tiny --max-turns 1
mix trinity.hitl.mock_loop --runtime-profile mock_tiny --max-turns 1
```

CUDA checks:

```bash
mix trinity.hitl.gpu
mix trinity.hitl.vector
mix trinity.hitl.head_route
mix trinity.hitl.base_qwen
mix trinity.hitl.adapted
```

## Prompt Eval

```bash
cd examples/qwen_router_prompt_eval
XLA_TARGET=cuda12 mix run lib/qwen_router_prompt_eval.exs -- \
  --snapshot fixtures/qwen_router_prompt_eval_logits.json \
  --determinism-runs 2
```

The eval is the 37-case route decision suite. It asserts agent id, role id,
margins, transcript-stable fields, and deterministic route hashes in-process.

## Where To Work

- Contracts: `core/trinity_contracts`
- Coordinator behavior: `core/trinity_coordinator_core`
- Sakana contract and pipeline: `core/trinity_sakana_contracts`,
  `core/trinity_sakana_pipeline`
- Bridges: `bridges/*`
- Standalone runtime: `apps/trinity_single_node`
- Operator tasks: `tools/trinity_ops`
- Prompt eval: `examples/qwen_router_prompt_eval`
