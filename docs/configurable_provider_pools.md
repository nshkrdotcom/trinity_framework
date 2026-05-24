# Configurable Provider Pools

Provider pools are explicit runtime inputs. The framework supports mock,
governed, inference-backed, and self-hosted routes without making provider SDKs
part of reusable contract packages.

## Command Surface

```bash
mix trinity.route.demo \
  --mock-provider \
  --runtime-profile mock_tiny \
  --max-turns 1

mix trinity.route.demo \
  --allow-live \
  --provider-pool governed \
  --governed-provider openai \
  --governed-model gpt-4.1-mini \
  --governed-api-key "$OPENAI_API_KEY"
```

The live form is deliberately explicit. The default route path must not spend
provider budget.

## Package Boundaries

- Contracts define provider-pool shapes.
- Bridges adapt those contracts to concrete provider packages.
- `tools/trinity_ops` owns operator flags.
- Applications own credential materialization.
