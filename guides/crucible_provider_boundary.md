# Trinity Crucible Provider Boundary

Trinity owns operator intent, request context, artifact layout, and reports. Crucible provider repos own model-surface negotiation, tap compilation, and backend-specific output options.

Operator paths must pass a non-nil tap plan into `SelfHostedInferenceCore.CrucibleRuntime.forward/4`. Unsupported hidden states, attention weights, logit lens, KV-cache metadata, or active injection surfaces are reported as capability degradation instead of being emulated.

Use `Trinity.Crucible.RuntimeProfile` for Crucible-scoped runtime identity inside operator planning. It records provider kind, model id, backend, artifact reference, supported capabilities, and trajectory layer preferences without making registry promotion decisions.
