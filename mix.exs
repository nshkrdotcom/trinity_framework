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
      docs: docs(),
      dialyzer: [plt_add_deps: :apps_direct],
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
        docs: :dev
      ]
    ]
  end

  defp package do
    [
      name: "trinity_framework",
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md assets guides),
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp deps do
    external_deps() ++
      [
        {:weld, "~> 0.8.2", only: [:dev, :test], runtime: false},
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
      dep(:aitrace)
    ]
  end

  defp dep(app), do: DependencySources.dep(app, __DIR__, override: true)

  defp aliases do
    [
      ci: [
        "deps.get",
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test",
        "credo --strict",
        "dialyzer --format short",
        "docs",
        &weld_verify/1
      ]
    ]
  end

  defp weld_verify(args) do
    {opts, _positional, invalid} = OptionParser.parse(args, strict: [artifact: :string])

    if invalid != [] do
      Mix.raise("Usage: mix ci [--artifact name]")
    end

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

    [
      run_weld_mix!(build_path, :dev, ["deps.get"]),
      run_weld_mix!(build_path, :dev, ["deps.compile"]),
      run_weld_mix!(build_path, :dev, ["compile", "--warnings-as-errors", "--no-compile-deps"]),
      run_weld_mix!(build_path, :test, ["test"]),
      run_weld_mix!(build_path, :dev, ["docs", "--warnings-as-errors"]),
      maybe_run_weld_mix!(build_path, :dev, ["hex.build"], plan.artifact.verify.hex_build),
      maybe_run_weld_mix!(
        build_path,
        :dev,
        ["hex.publish", "--dry-run", "--yes"],
        plan.artifact.verify.hex_build and plan.artifact.verify.hex_publish
      )
    ]

    Mix.shell().info("Verified artifact in #{build_path}")
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
    |> then(&Regex.scan(~r/import_config\s+"([^"]+\/runtime\.exs)"/, &1, capture: :all_but_first))
    |> List.flatten()
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
    String.replace(source, ~r/\A\s*import Config\s*/, "")
  end

  defp run_weld_mix!(build_path, env, args) do
    env_vars = [{"MIX_ENV", Atom.to_string(env)}]

    {output, status} =
      System.cmd("mix", args, cd: build_path, env: env_vars, stderr_to_stdout: true)

    if status != 0 do
      Mix.raise("""
      generated project command failed: MIX_ENV=#{env} mix #{Enum.join(args, " ")}

      #{output}
      """)
    end

    :ok
  end

  defp maybe_run_weld_mix!(build_path, env, args, true), do: run_weld_mix!(build_path, env, args)
  defp maybe_run_weld_mix!(_build_path, _env, _args, false), do: :ok

  defp docs do
    [
      main: "readme",
      logo: "assets/trinity_framework.svg",
      assets: %{"assets" => "assets"},
      extras: [
        "README.md",
        "CHANGELOG.md",
        "guides/onboarding.md",
        "guides/system_architecture.md",
        "guides/operations_qc.md",
        "guides/artifact_distribution.md",
        "guides/artifacts_and_export.md",
        "guides/runtime_profiles.md",
        "guides/evals.md",
        "guides/python_parity_reconstruction.md",
        "guides/stage_checks_and_tolerances.md",
        "guides/svd_generation_runbook.md",
        "guides/provider_service_hardening.md",
        "guides/troubleshooting.md"
      ],
      groups_for_extras: [
        "Getting Started": [
          "guides/onboarding.md"
        ],
        "System Architecture": [
          "guides/system_architecture.md",
          "guides/runtime_profiles.md"
        ],
        "Artifacts & Pipelines": [
          "guides/artifacts_and_export.md",
          "guides/artifact_distribution.md"
        ],
        "Evaluation & QC": [
          "guides/evals.md",
          "guides/operations_qc.md",
          "guides/stage_checks_and_tolerances.md"
        ],
        "Operations & Runbooks": [
          "guides/svd_generation_runbook.md",
          "guides/provider_service_hardening.md",
          "guides/python_parity_reconstruction.md",
          "guides/troubleshooting.md"
        ]
      ],
      source_ref: "main",
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end
end
