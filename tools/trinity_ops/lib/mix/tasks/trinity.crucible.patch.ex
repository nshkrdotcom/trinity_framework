defmodule Mix.Tasks.Trinity.Crucible.Patch do
  @moduledoc "Runs a local tiny-model Crucible activation patch."
  @shortdoc "Runs a local Crucible activation patch"

  use Mix.Task

  alias Trinity.Ops.Tasks

  @impl true
  def run(argv), do: Tasks.run(:trinity_crucible_patch, argv)
end
