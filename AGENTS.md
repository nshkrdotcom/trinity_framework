# AGENTS.md

`trinity_framework` owns reusable TRINITY router and coordination mechanics.
It must stay framework-only: no Mezzanine, Citadel, Jido, AppKit, provider SDK,
lower runtime, or `jido_skill` dependency is allowed.

Runtime code, tests, examples, build helpers, generators, and checked-in
generated code must remain regex-free, dynamic-atom-free, and ambient-env-free.
Use fixed-string scans and structured validators.

This repo is an existing Weld consumer. Keep Weld as a normal published Hex
dependency and do not replace it with a committed path dependency.

Committed dependency tuples are the standalone defaults. Mix Workspace Ops may
replace only their source coordinates through its tuple-first bootstrap seam;
do not add repository-local source resolvers, machine paths, or ambient source
selection variables.

Runtime application code under `lib/**`, examples, Mix tasks, and SDK helpers
must not call direct OS environment APIs such as `System.get_env/1`,
`System.fetch_env/1`, `System.fetch_env!/1`, `System.put_env/2`,
`System.delete_env/1`, or `System.get_env/0`. Runtime environment reads belong
in `config/runtime.exs` or a `Config.Provider`; library APIs should receive
explicit options, config structs, or caller-owned credential providers.
