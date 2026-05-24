# Service Buildout

The framework can run as a single-node application today and can be embedded by
larger services through public contracts.

## Single-Node Path

`apps/trinity_single_node` wires contracts, bridges, runtime profile selection,
artifact loading, provider dispatch, and trace output.

Use mock profiles first:

```bash
mix trinity.gates --fast
mix trinity.route.demo --mock-provider --runtime-profile mock_tiny --max-turns 1
```

Then run CUDA/adapted checks on GPU hosts.

## Service Integration Path

1. Depend on the published framework packages.
2. Provide runtime config through application config or config providers.
3. Pass provider credentials through explicit app-owned boundaries.
4. Persist trace events through the trace bridge or application sink.
5. Keep live provider execution gated and auditable.

The framework should not grow product-specific app dependencies to satisfy a
service integration. Product applications integrate from their side.
