# Python Torch Trace Provider

Purpose: emit Crucible trace events from real Hugging Face Transformers
models through PyTorch when Elixir-native providers cannot expose required
internals.

## What It Captures

`tools/python/crucible_torch_trace.py` runs a real `AutoModelForCausalLM`
forward pass and a manual greedy generation loop. It writes bounded summaries,
not raw tensor arrays.

Captured signals:

- `input_ids`
- `attention_mask`
- `final_logits`
- `hidden_state`
- `attention_weights`
- `generation_step_logits`
- `generation_token`
- `decoded_text`

The worker writes:

- `tmp/crucible_v5/traces/python/<name>.trace.jsonl`
- `tmp/crucible_v5/capability_reports/<name>.capability_report.json`
- `tmp/crucible_v5/reports/<name>.python_trace_report.json`

## Commands

Run the tiny GPT-2 control:

```bash
python3 tools/python/crucible_torch_trace.py \
  --model-id hf-internal-testing/tiny-random-gpt2 \
  --model-family gpt2 \
  --prompt "Hi" \
  --artifact-root tmp/crucible_v5 \
  --trace-name python_torch_tiny_random_gpt2_phase15 \
  --max-new-tokens 4 \
  --top-k 5
```

Run standard GPT-2:

```bash
python3 tools/python/crucible_torch_trace.py \
  --model-id gpt2 \
  --model-family gpt2 \
  --prompt "Hi" \
  --artifact-root tmp/crucible_v5 \
  --trace-name python_torch_gpt2_phase15 \
  --max-new-tokens 3 \
  --top-k 5
```

Replay through Trinity:

```bash
mix trinity.crucible.inspect \
  --trace tmp/crucible_v5/traces/python/python_torch_gpt2_phase15.trace.jsonl \
  --artifact-root tmp/crucible_v5

mix trinity.crucible.matrix_eval \
  --trace tmp/crucible_v5/traces/python \
  --artifact-root tmp/crucible_v5
```

## Boundary Decision

For V5, this worker is an external trace provider, not a supervised Python
runtime. `snakepit` is the candidate long-lived Python process pool and
`snakebridge` is the candidate higher-level Python binding/contract layer. They
are not inserted into this phase because the acceptance gate is trace proof over
real model internals, and the stable contract is the Crucible JSONL trace plus
capability report.

The next supervised provider phase should put Python worker lifecycle under
`self_hosted_inference_core` provider behavior after the trace contract has
stayed stable.
