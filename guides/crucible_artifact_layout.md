# Trinity Crucible Artifact Layout

Crucible operator commands write under `tmp/crucible_v5` by default:

- `reports/` for operator JSON reports.
- `traces/` for captured or copied trace artifacts.
- `policy_decisions/` for deterministic policy outputs.
- `route_decisions/` for Trinity route decision projections.
- `transcripts/` for command transcripts.

Use `--artifact-root` to move the whole layout for a run.
