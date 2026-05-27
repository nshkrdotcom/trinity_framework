# Runtime Profiles

Runtime profiles select how the single-node app loads and runs the Qwen/Sakana
route path. The profile is a Trinity runtime choice; the Crucible libraries do
not require Qwen or the modified Trinity 0.6B artifact.

Common profiles:

- `cuda_exla`: CUDA EXLA route path. Use for release proof on NVIDIA hosts.
- `host_exla`: host EXLA route path. Useful for CPU smoke work.
- `mock_tiny`: no heavy model, used by command and orchestration smoke tests.
- `emlx`: Apple Silicon lane. External hardware gate.
- `emily`: profile-specific margin lane.

## Use A Profile In Commands

```bash
mix trinity.route.demo --mock-provider --runtime-profile mock_tiny --max-turns 1
mix trinity.hitl.mock_loop --runtime-profile mock_tiny --max-turns 1
mix trinity.hitl.adapted --runtime-profile cuda_exla
mix trinity.crucible.matrix_eval --runtime-profile mock_tiny
```

Eval profile:

```bash
cd examples/qwen_router_prompt_eval
XLA_TARGET=cuda12 mix run lib/qwen_router_prompt_eval.exs -- \
  --runtime-profile cuda_exla \
  --snapshot fixtures/qwen_router_prompt_eval_logits.json \
  --determinism-runs 2
```

Export profile:

```bash
XLA_TARGET=cuda12 mix trinity.sakana.export_adapted --runtime-profile cuda_exla
```

## Margins

Each profile may use different default route margins. The eval supports
overrides:

```bash
mix run lib/qwen_router_prompt_eval.exs -- \
  --min-agent-margin 0.01 \
  --min-role-margin 0.01
```

## EMLX

The EMLX profile is intentionally not validated on Linux CUDA hosts. Record it
as an Apple Silicon hardware gate unless an Apple Silicon runner is available.
