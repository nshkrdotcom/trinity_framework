# Onboarding

Run the local gate from this repository root:

```bash
mix deps.get
mix ci
```

The framework exports ref-only TRINITY contracts. Product and governed runtime
repos consume these contracts through their own orchestration layers.
