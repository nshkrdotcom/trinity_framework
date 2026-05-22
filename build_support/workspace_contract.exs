defmodule TrinityFramework.Build.WorkspaceContract do
  @moduledoc false

  @package_paths [
    ".",
    "core/trinity_contracts",
    "core/trinity_coordinator_core",
    "core/trinity_sakana_contracts",
    "core/trinity_sakana_pipeline",
    "bridges/trinity_bridge_self_hosted_inference",
    "bridges/trinity_bridge_inference",
    "bridges/trinity_bridge_trace",
    "apps/trinity_single_node",
    "tools/trinity_ops",
    "examples/qwen_router_prompt_eval"
  ]
  @active_project_globs [
    ".",
    "core/trinity_contracts",
    "core/trinity_coordinator_core",
    "core/trinity_sakana_contracts",
    "core/trinity_sakana_pipeline",
    "bridges/trinity_bridge_self_hosted_inference",
    "bridges/trinity_bridge_inference",
    "bridges/trinity_bridge_trace",
    "apps/trinity_single_node",
    "tools/trinity_ops",
    "examples/qwen_router_prompt_eval"
  ]

  def package_paths, do: @package_paths
  def active_project_globs, do: @active_project_globs
end
