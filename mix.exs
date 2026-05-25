unless Code.ensure_loaded?(DependencySources) do
  Code.require_file("build_support/dependency_sources.exs", __DIR__)
end

Code.require_file("build_support/workspace_contract.exs", __DIR__)

defmodule TrinityFramework.MixProject do
  use Mix.Project

  alias TrinityFramework.Build.WorkspaceContract

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/trinity_framework"

  def project do
    [
      app: :trinity_framework,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      blitz_workspace: blitz_workspace(),
      docs: docs(),
      dialyzer: [plt_add_deps: :apps_direct, plt_add_apps: [:mix, :blitz, :weld]],
      name: "TRINITY Framework",
      description: "Reusable TRINITY router and coordination framework",
      source_url: @source_url,
      homepage_url: @source_url,
      package_paths: WorkspaceContract.package_paths(),
      package: package()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  def cli do
    [
      preferred_envs: [
        ci: :test,
        credo: :test,
        dialyzer: :test,
        docs: :dev,
        "monorepo.test": :test,
        "monorepo.credo": :test,
        "monorepo.dialyzer": :test,
        "monorepo.docs": :dev
      ]
    ]
  end

  defp package do
    [
      name: "trinity_framework",
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md assets guides docs),
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp deps do
    external_deps() ++
      [
        {:weld, "~> 0.8.2", only: [:dev, :test], runtime: false},
        {:blitz, "~> 0.3.0", runtime: false},
        {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
        {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
        {:ex_doc, "~> 0.40.1", only: [:dev, :test], runtime: false},

        # Deconstructed Sub-packages
        {:trinity_contracts, path: "core/trinity_contracts"},
        {:trinity_coordinator_core, path: "core/trinity_coordinator_core"},
        {:trinity_sakana_contracts, path: "core/trinity_sakana_contracts"},
        {:trinity_sakana_pipeline, path: "core/trinity_sakana_pipeline"},
        {:trinity_bridge_self_hosted_inference,
         path: "bridges/trinity_bridge_self_hosted_inference"},
        {:trinity_bridge_inference, path: "bridges/trinity_bridge_inference"},
        {:trinity_bridge_trace, path: "bridges/trinity_bridge_trace"},
        {:trinity_single_node, path: "apps/trinity_single_node"},
        {:trinity_ops, path: "tools/trinity_ops"},
        {:qwen_router_prompt_eval, path: "examples/qwen_router_prompt_eval"}
      ]
  end

  defp external_deps do
    [
      dep(:crucible_safetensors),
      dep(:crucible_factorization),
      dep(:crucible_tensor_patch),
      dep(:crucible_model_registry),
      dep(:self_hosted_inference_core),
      dep(:self_hosted_inference_bumblebee),
      dep(:execution_plane),
      dep(:execution_plane_process),
      dep(:inference),
      dep(:outer_brain_context_abi),
      dep(:aitrace)
    ]
  end

  defp dep(app), do: DependencySources.dep(app, __DIR__, override: true)

  defp aliases do
    monorepo_aliases = [
      "monorepo.deps.get": ["blitz.workspace.impact deps_get --"],
      "monorepo.format": ["blitz.workspace.impact format --"],
      "monorepo.compile": ["blitz.workspace.impact compile --"],
      "monorepo.test": ["blitz.workspace.impact test --"],
      "monorepo.credo": ["blitz.workspace.impact credo --"],
      "monorepo.dialyzer": ["blitz.workspace.impact dialyzer --"],
      "monorepo.docs": ["blitz.workspace.impact docs --"],
      "mr.deps.get": ["monorepo.deps.get"],
      "mr.format": ["monorepo.format"],
      "mr.compile": ["monorepo.compile"],
      "mr.test": ["monorepo.test"],
      "mr.credo": ["monorepo.credo"],
      "mr.dialyzer": ["monorepo.dialyzer"],
      "mr.docs": ["monorepo.docs"]
    ]

    [
      ci: [
        "deps.get",
        "monorepo.deps.get",
        "monorepo.format --check-formatted",
        "monorepo.compile",
        "monorepo.test",
        "monorepo.credo --strict",
        "monorepo.dialyzer --format short",
        "monorepo.docs --warnings-as-errors",
        &weld_verify/1
      ],
      "weld.verify": [&weld_verify/1],
      "docs.root": ["docs"]
    ] ++ monorepo_aliases
  end

  defp weld_verify(args) do
    {opts, _positional, invalid} = OptionParser.parse(args, strict: [artifact: :string])

    if invalid != [] do
      Mix.raise("Usage: mix ci [--artifact name]")
    end

    Mix.Task.run("deps.loadpaths", [])

    "build_support/weld.exs"
    |> Weld.Plan.build!(artifact: opts[:artifact])
    |> verify_weld_plan!()
  end

  # Weld 0.8.2 projects package runtime configs with import_config/1, which
  # Elixir rejects from generated root runtime.exs. Keep the normal projected
  # artifact gates, but inline those package runtime configs before verifying.
  defp verify_weld_plan!(plan) do
    projection = Weld.Projector.project!(plan)
    build_path = projection.build_path

    inline_weld_runtime_imports!(build_path)

    verification_results = [
      run_weld_mix!(build_path, :dev, ["deps.get"]),
      run_weld_mix!(build_path, :dev, ["deps.compile"]),
      run_weld_mix!(build_path, :dev, ["compile", "--warnings-as-errors", "--no-compile-deps"]),
      run_weld_mix!(build_path, :test, ["test"]),
      run_weld_mix!(build_path, :dev, ["docs", "--warnings-as-errors"]),
      maybe_run_weld_mix!(build_path, :dev, ["hex.build"], plan.artifact.verify.hex_build,
        reason: :artifact_opted_out
      ),
      maybe_run_weld_mix!(
        build_path,
        :dev,
        ["hex.publish", "--dry-run", "--yes"],
        plan.artifact.verify.hex_build and plan.artifact.verify.hex_publish,
        reason:
          if(plan.artifact.verify.hex_build,
            do: :artifact_opted_out,
            else: :hex_build_disabled
          )
      )
    ]

    write_weld_lockfile!(plan, projection, verification_results)
    Mix.shell().info("Verified artifact in #{build_path}")
  end

  defp write_weld_lockfile!(plan, projection, verification_results) do
    projection_report =
      Map.take(projection, [
        :build_path,
        :copied_files,
        :package_files,
        :git_revision,
        :tree_digest
      ])

    lockfile = Weld.Lockfile.build(plan, projection_report, verification_results)
    File.write!(projection.lockfile_path, Weld.Lockfile.encode!(lockfile))
  end

  defp inline_weld_runtime_imports!(build_path) do
    runtime_path = Path.join([build_path, "config", "runtime.exs"])

    if File.regular?(runtime_path) do
      runtime_path
      |> weld_runtime_imports()
      |> write_inlined_weld_runtime_sources!(runtime_path)
    end
  end

  defp weld_runtime_imports(runtime_path) do
    runtime_path
    |> File.read!()
    |> String.split(["\n", "\r\n"])
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&String.starts_with?(&1, "import_config"))
    |> Enum.map(fn line ->
      case String.split(line, "\"") do
        [_, path, _] -> path
        _ -> nil
      end
    end)
    |> Enum.filter(& &1)
  end

  defp write_inlined_weld_runtime_sources!([], _runtime_path), do: :ok

  defp write_inlined_weld_runtime_sources!(imports, runtime_path) do
    config_root = Path.dirname(runtime_path)

    inlined_sources =
      Enum.map_join(imports, "\n\n", &inlined_weld_runtime_source(config_root, &1))

    File.write!(runtime_path, "import Config\n\n" <> String.trim(inlined_sources) <> "\n")
  end

  defp inlined_weld_runtime_source(config_root, relative_path) do
    import_path = Path.join(config_root, relative_path)

    unless File.regular?(import_path) do
      Mix.raise("projected runtime config import not found: #{import_path}")
    end

    """
    # Inlined from #{relative_path}; runtime.exs cannot call import_config.
    #{strip_weld_import_config_header(File.read!(import_path))}
    """
  end

  defp strip_weld_import_config_header(source) do
    source
    |> String.split(["\n", "\r\n"])
    |> drop_import_config_header()
    |> Enum.join("\n")
  end

  defp drop_import_config_header([]), do: []

  defp drop_import_config_header([line | rest]) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" -> drop_import_config_header(rest)
      trimmed == "import Config" -> rest
      true -> [line | rest]
    end
  end

  defp run_weld_mix!(build_path, env, args) do
    env_vars = [{"MIX_ENV", Atom.to_string(env)}]

    Mix.shell().info("Running projected command: MIX_ENV=#{env} mix #{Enum.join(args, " ")}")

    {_, status} =
      System.cmd("mix", args,
        cd: build_path,
        env: env_vars,
        stderr_to_stdout: true,
        into: IO.stream()
      )

    if status != 0 do
      Mix.raise("generated project command failed: MIX_ENV=#{env} mix #{Enum.join(args, " ")}")
    end

    %{task: Enum.join(args, " "), env: env, status: :ok}
  end

  defp maybe_run_weld_mix!(build_path, env, args, true, _opts),
    do: run_weld_mix!(build_path, env, args)

  defp maybe_run_weld_mix!(_build_path, env, args, false, opts) do
    %{task: Enum.join(args, " "), env: env, status: :skipped, reason: opts[:reason]}
  end

  defp docs do
    [
      main: "readme",
      logo: "assets/trinity_framework.svg",
      assets: %{"assets" => "assets"},
      extras: [
        "README.md",
        "CHANGELOG.md",
        "guides/onboarding.md",
        "guides/current_direction.md",
        "guides/system_architecture.md",
        "guides/service_buildout.md",
        "guides/router_fabric.md",
        "guides/operations_qc.md",
        "guides/artifact_distribution.md",
        "guides/artifacts_and_export.md",
        "guides/runtime_profiles.md",
        "guides/evals.md",
        "guides/python_parity_reconstruction.md",
        "guides/stage_checks_and_tolerances.md",
        "guides/svd_generation_runbook.md",
        "guides/provider_service_hardening.md",
        "guides/troubleshooting.md",
        "docs/agent_slot_provider_mapping.md",
        "docs/bumblebee_unpin_playbook.md",
        "docs/configurable_provider_pools.md",
        "docs/coordination_head_variants.md",
        "docs/elixir_svd_decomposition.md",
        "docs/production_qwen_slm_profile.md",
        "docs/production_runbook.md",
        "docs/provider_smoke_tests.md",
        "docs/sakana_adapted_artifact_plan.md",
        "docs/sakana_svd_byte_match_rigor_plan.md",
        "docs/sakana_svd_parity_debug_checklist.md",
        "docs/trace_persistence.md"
      ],
      groups_for_extras: [
        "Getting Started": [
          "guides/onboarding.md",
          "guides/current_direction.md"
        ],
        "System Architecture": [
          "guides/system_architecture.md",
          "guides/runtime_profiles.md",
          "guides/service_buildout.md",
          "guides/router_fabric.md"
        ],
        "Artifacts & Pipelines": [
          "guides/artifacts_and_export.md",
          "guides/artifact_distribution.md",
          "docs/sakana_adapted_artifact_plan.md",
          "docs/elixir_svd_decomposition.md"
        ],
        "Evaluation & QC": [
          "guides/evals.md",
          "guides/operations_qc.md",
          "guides/stage_checks_and_tolerances.md",
          "docs/sakana_svd_byte_match_rigor_plan.md",
          "docs/sakana_svd_parity_debug_checklist.md"
        ],
        "Operations & Runbooks": [
          "guides/svd_generation_runbook.md",
          "guides/provider_service_hardening.md",
          "guides/python_parity_reconstruction.md",
          "guides/troubleshooting.md",
          "docs/agent_slot_provider_mapping.md",
          "docs/bumblebee_unpin_playbook.md",
          "docs/configurable_provider_pools.md",
          "docs/coordination_head_variants.md",
          "docs/production_qwen_slm_profile.md",
          "docs/production_runbook.md",
          "docs/provider_smoke_tests.md",
          "docs/trace_persistence.md"
        ]
      ],
      source_ref: "main",
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  defp blitz_workspace do
    [
      root: __DIR__,
      projects: WorkspaceContract.active_project_globs(),
      isolation: [
        deps_path: true,
        build_path: true,
        lockfile: true,
        hex_home: "_build/hex",
        unset_env: ["HEX_API_KEY", "SSLKEYLOGFILE"]
      ],
      parallelism: [
        env: "TRINITY_FRAMEWORK_MONOREPO_MAX_CONCURRENCY",
        max_concurrency: nil,
        multiplier: :auto,
        base: [
          deps_get: 4,
          format: 4,
          compile: 4,
          test: 4,
          credo: 2,
          dialyzer: 2,
          docs: 4
        ],
        overrides: []
      ],
      tasks: [
        deps_get: [args: ["deps.get"], preflight?: false],
        format: [args: ["format"]],
        compile: [args: ["compile", "--warnings-as-errors"]],
        test: [args: ["test"], mix_env: "test", color: true],
        credo: [args: ["credo"]],
        dialyzer: [args: ["dialyzer", "--force-check"], mix_env: "test"],
        docs: [args: ["docs"]]
      ]
    ]
  end
end
