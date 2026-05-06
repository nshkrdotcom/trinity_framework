# AGENTS.md

`trinity_framework` owns reusable TRINITY router and coordination mechanics.
It must stay framework-only: no Mezzanine, Citadel, Jido, AppKit, provider SDK,
lower runtime, or `jido_skill` dependency is allowed.

Runtime code, tests, examples, build helpers, generators, and checked-in
generated code must remain regex-free, dynamic-atom-free, and ambient-env-free.
Use fixed-string scans and structured validators.
