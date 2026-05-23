defmodule Mix.Tasks.Trinity.Artifact.Fetch do
  @moduledoc """
  Downloads and SHA-verifies the adapted Qwen3 artifact bundle.
  """
  @shortdoc "Downloads and SHA-verifies the adapted Qwen3 artifact bundle"
  use Mix.Task
  alias Trinity.Ops.Tasks

  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_artifact_fetch, argv)
end
