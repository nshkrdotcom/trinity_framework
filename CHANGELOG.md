# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

- Make runtime artifact provenance immutable: manifest and pin data are the
  source of truth, identity options are validated as assertions, and
  provenance-shaping runtime options fail closed.
- Expand V5 Trinity Crucible trace replay to files, directories, and globs, with
  policy decision and route decision artifacts written under `tmp/crucible_v5`.
- Add V5 live inspect options for real hosted model IDs, backends,
  architectures, artifact roots, trace names, and forward timeouts.
- Add V5 live matrix eval artifact output, role-boundary stability reports, and
  the `--limit 3`, `--limit 10`, and `--limit 37` live evaluation ladder.
- Add a provider-identity branching audit proving Crucible routing records
  provider kind without branching policy behavior on provider identity.
- Add `tools/python/crucible_torch_trace.py`, an external Python/PyTorch
  Crucible trace provider that captures final logits, hidden states, attention
  weights, and manual generation-step logits from real Transformers models.
- Add V4 Crucible trace replay and live hosted-runtime modes for
  `mix trinity.crucible.inspect`.
- Add V4 live matrix smoke support for
  `mix trinity.crucible.matrix_eval --live --limit 3`.
- Add synthetic Python-shaped and black-box V4 trace fixtures under `runs/`.
