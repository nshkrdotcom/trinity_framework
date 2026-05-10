<p align="center">
  <img src="assets/trinity_framework.svg" alt="TRINITY Framework" width="220" />
</p>

<p align="center">
  <a href="https://github.com/nshkrdotcom/trinity_framework"><img alt="GitHub" src="https://img.shields.io/badge/github-nshkrdotcom%2Ftrinity__framework-24292f?logo=github" /></a>
  <img alt="Elixir" src="https://img.shields.io/badge/elixir-1.17%2B-4b275f?logo=elixir" />
  <img alt="Weld" src="https://img.shields.io/badge/weld-0.8.0-2563eb" />
  <img alt="License" src="https://img.shields.io/badge/license-MIT-0f766e" />
</p>

# TRINITY Framework

`trinity_framework` is the reusable TRINITY router and coordination contract
package. It owns deterministic framework mechanics only:

- router artifact, extractor, router head, and router decision contracts;
- role pack registry contracts;
- provider pool contracts with local, remote, self-hosted, mock, CLI, HTTP, and
  governed inference slots;
- verifier, trace, session, artifact, and coordination pattern contracts;
- memory-default session persistence posture.

The framework does not own governed platform orchestration, authority, provider
credentials, self-hosted process lifecycle, AppKit product surfaces, or
TRINITY Qwen/Sakana buildout artifacts. Those stay in their owning repos.

## QC

```bash
mix ci
```
