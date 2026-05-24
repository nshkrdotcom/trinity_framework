# Provider Smoke Tests

Provider smoke tests prove that route decisions can dispatch through the
configured provider bridge without making live calls by default.

## Mock Smoke

```bash
mix trinity.route.demo \
  --mock-provider \
  --runtime-profile mock_tiny \
  --max-turns 1 \
  --trace-out tmp/trinity_route_demo.jsonl

mix trinity.hitl.mock_loop \
  --runtime-profile mock_tiny \
  --max-turns 1 \
  --trace-out tmp/trinity_mock_loop.jsonl
```

## Live Smoke

Live smoke requires explicit `--allow-live`, provider selection, model
selection, and caller-owned credentials.

```bash
mix trinity.route.demo \
  --allow-live \
  --provider-pool governed \
  --governed-provider openai \
  --governed-model gpt-4.1-mini \
  --governed-api-key "$OPENAI_API_KEY"
```
