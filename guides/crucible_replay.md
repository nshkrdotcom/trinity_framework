# Trinity Crucible Replay

`mix trinity.crucible.replay --trace tools/trinity_ops/test/fixtures/crucible_minimal_forward_trace.jsonl` loads a real JSONL trace, validates its shape, evaluates deterministic Crucible policy, writes policy and route artifacts, and emits an operator report.

Replay-safety status is reported separately from shape validation because older fixtures may not contain provider capability reports. Do not treat a fixture as replay-safe unless the report says the replay validation level is `ok`.
