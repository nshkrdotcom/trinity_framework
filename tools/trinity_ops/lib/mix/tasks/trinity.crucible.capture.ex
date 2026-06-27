defmodule Mix.Tasks.Trinity.Crucible.Capture do
  @moduledoc "Runs a local tiny-model Crucible activation capture."
  @shortdoc "Runs a local Crucible activation capture"

  use Mix.Task

  alias Trinity.Ops.Tasks

  @impl true
  def run(argv), do: Tasks.run(:trinity_crucible_capture, argv)
end
