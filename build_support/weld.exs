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

  @local_git_dependencies MapSet.new([
                            :crucible_safetensors,
                            :crucible_factorization,
                            :crucible_tensor_patch,
                            :self_hosted_inference_bumblebee
                          ])

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
        docs: ["README.md"],
        assets: ["assets/trinity_framework.svg"]
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

    if MapSet.member?(@local_git_dependencies, app) do
      [
        opts: [
          git: Path.expand(Map.fetch!(config, :path), @repo_root),
          branch: "main",
          override: true
        ]
      ]
    else
      github = Map.fetch!(config, :github)
      [opts: github_opts(github)]
    end
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
