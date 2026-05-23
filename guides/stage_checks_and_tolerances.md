# Stage Checks And Tolerances

Stage checks compare semantic pipeline outputs across Python, Elixir, CPU, and
CUDA paths. The goal is to catch orientation, dtype, tensor-name, and hash drift
without requiring every environment to be byte-identical.

## Commands

```bash
mix trinity.sakana.parity_sample \
  --semantic-only \
  --no-cuda \
  --out tmp/sakana_parity_sample.json
```

```bash
mix trinity.sakana.large_tensor_chunks \
  --python-report priv/sakana_trinity/reference/sakana_python_reference_manifest.json \
  --out tmp/sakana_large_tensor_chunks.json \
  --chunk-rows 2048 \
  --no-cuda
```

```bash
mix trinity.sakana.router_trace \
  --out tmp/sakana_router_trace.json
```

## Stable Fields

The route eval treats these as decision-stable:

- selected agent id;
- selected role id;
- token count;
- transcript hash;
- in-process route hash determinism.

CUDA route hashes may vary across separate process launches because compiler and
runtime details can affect floating-point traces. Use route hashes for
in-process determinism and diagnostics, not as cross-launch byte identity.

## Historical Byte Parity

Historical byte parity is stricter than release readiness. It requires the
original Python provenance, SVD weights, and environment. If those inputs are not
available, record the waiver and rely on semantic plus route-decision parity.

