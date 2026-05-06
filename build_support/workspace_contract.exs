defmodule TrinityFramework.Build.WorkspaceContract do
  @moduledoc false

  @package_paths ["."]
  @active_project_globs ["."]

  def package_paths, do: @package_paths
  def active_project_globs, do: @active_project_globs
end
