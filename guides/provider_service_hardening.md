# Provider Service Hardening

TRINITY routes to local/self-hosted and provider-backed execution through
explicit bridges. The framework does not own provider secrets or product
orchestration.

## Boundaries

- Provider transport belongs to `:inference`.
- Trace primitives belong to AITrace.
- Self-hosted model lifecycle belongs to `self_hosted_inference_core` and
  `self_hosted_inference_bumblebee`.
- Product surfaces and platform governance integrate from external product
  systems; they are not direct framework dependencies.

## Safe Smoke Commands

```bash
mix trinity.route.demo --mock-provider --runtime-profile mock_tiny --max-turns 1
mix trinity.hitl.mock_loop --runtime-profile mock_tiny --max-turns 1
```

## Live Providers

Live provider calls must be explicit. Do not make live calls from default QC.
Use governed refs and credential refs rather than embedding secrets in source.

Representative route demo flags:

```bash
mix trinity.route.demo \
  --allow-live \
  --governed-provider openai \
  --governed-model gpt-5 \
  --governed-authority-ref authority://example \
  --governed-credential-ref credential://example
```

## Trace And Redaction

Use `trinity_bridge_trace` and AITrace primitives for deterministic JSONL,
hashing, context, and redaction. Product code should consume approved public
projections rather than importing lower model/runtime layers directly.
