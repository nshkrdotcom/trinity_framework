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
