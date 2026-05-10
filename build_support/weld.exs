Code.require_file("workspace_contract.exs", __DIR__)

defmodule TrinityFramework.Build.WeldContract do
  @moduledoc false

  def manifest do
    [
      workspace: [
        root: "..",
        project_globs: TrinityFramework.Build.WorkspaceContract.active_project_globs()
      ],
      classify: [
        tooling: ["."]
      ],
      publication: [
        internal_only: ["."]
      ],
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
end

TrinityFramework.Build.WeldContract.manifest()
