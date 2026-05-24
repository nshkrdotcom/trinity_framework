Code.require_file("workspace_contract.exs", __DIR__)

defmodule TrinityFramework.Build.WeldContract do
  @moduledoc false

  alias TrinityFramework.Build.WorkspaceContract

  @repo_root Path.expand("..", __DIR__)

  @manifest_dependencies [
    :crucible_safetensors,
    :crucible_factorization,
    :crucible_tensor_patch,
    :crucible_model_registry,
    :self_hosted_inference_core,
    :self_hosted_inference_bumblebee,
    :execution_plane,
    :execution_plane_process,
    :inference,
    :aitrace
  ]

  @artifact_docs [
    "README.md",
    "CHANGELOG.md",
    "guides/onboarding.md",
    "guides/current_direction.md",
    "guides/system_architecture.md",
    "guides/service_buildout.md",
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
  ]

  @artifact_assets [
    "assets/trinity_framework.svg",
    "LICENSE",
    "priv/sakana_trinity/artifact_pin.json",
    "priv/sakana_trinity/reference/sakana_python_reference_manifest.json",
    "examples/qwen_router_prompt_eval/fixtures"
  ]

  def manifest do
    [
      workspace: [
        root: "..",
        project_globs: WorkspaceContract.active_project_globs()
      ],
      classify: [
        tooling: ["."]
      ],
      publication: [
        internal_only: ["."]
      ],
      dependencies: dependencies(),
      artifacts: [
        trinity_framework: artifact()
      ]
    ]
  end

  def artifact do
    [
      roots: ["."],
      package: [
        name: "trinity_framework",
        otp_app: :trinity_framework,
        version: "0.1.0",
        description: "Reusable TRINITY router and coordination framework"
      ],
      output: [
        docs: @artifact_docs,
        assets: @artifact_assets
      ],
      verify: [
        artifact_tests: ["test"],
        hex_build: false,
        hex_publish: false
      ]
    ]
  end

  defp dependencies do
    Enum.map(@manifest_dependencies, fn app ->
      {app, manifest_dependency(app)}
    end)
  end

  defp manifest_dependency(app) do
    config = Map.fetch!(dependency_configs(), app)
    github = Map.fetch!(config, :github)
    [opts: github_opts(github)]
  end

  defp dependency_configs do
    {config, _binding} =
      @repo_root
      |> Path.join("build_support/dependency_sources.config.exs")
      |> Code.eval_file()

    Map.new(config[:deps], fn {app, dep_config} -> {app, Map.new(dep_config)} end)
  end

  defp github_opts(github) do
    github = Map.new(github)
    repo = Map.fetch!(github, :repo)

    opts =
      github
      |> Map.take([:branch, :ref, :tag, :subdir])
      |> Enum.sort_by(fn {key, _value} -> key end)

    Keyword.merge([github: repo], opts)
  end
end

TrinityFramework.Build.WeldContract.manifest()
