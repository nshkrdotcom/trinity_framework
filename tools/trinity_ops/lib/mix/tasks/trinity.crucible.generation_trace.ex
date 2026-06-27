defmodule Mix.Tasks.Trinity.Crucible.GenerationTrace do
  @moduledoc "Runs a local tiny-model Crucible generation trace."
  @shortdoc "Runs a local Crucible generation trace"

  use Mix.Task

  alias Trinity.Ops.Tasks

  @impl true
  def run(argv), do: Tasks.run(:trinity_crucible_generation_trace, argv)
end
