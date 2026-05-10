# AGENTS.md

`trinity_framework` owns reusable TRINITY router and coordination mechanics.
It must stay framework-only: no Mezzanine, Citadel, Jido, AppKit, provider SDK,
lower runtime, or `jido_skill` dependency is allowed.

Runtime code, tests, examples, build helpers, generators, and checked-in
generated code must remain regex-free, dynamic-atom-free, and ambient-env-free.
Use fixed-string scans and structured validators.

This repo is an existing Weld consumer. Keep Weld on the current published Hex
line, `{:weld, "~> 0.8.1", only: [:dev, :test], runtime: false}`, and do not
replace it with a path dependency in committed steady state.
Weld checks helper drift, dependency-source manifests, clone/publish checks, and
publish order for this repo.

Dependency source selection is owned by
`build_support/dependency_sources.exs` and
`build_support/dependency_sources.config.exs`. Use
`.dependency_sources.local.exs` only for local uncommitted overrides; dependency
source selection must not use environment variables.

Runtime application code under `lib/**`, examples, Mix tasks, and SDK helpers
must not call direct OS environment APIs such as `System.get_env/1`,
`System.fetch_env/1`, `System.fetch_env!/1`, `System.put_env/2`,
`System.delete_env/1`, or `System.get_env/0`. Runtime environment reads belong
in `config/runtime.exs` or a `Config.Provider`; library APIs should receive
explicit options, config structs, or caller-owned credential providers.
