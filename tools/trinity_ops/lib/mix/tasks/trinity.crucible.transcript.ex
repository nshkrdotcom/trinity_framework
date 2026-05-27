defmodule Mix.Tasks.Trinity.Crucible.Transcript do
  @moduledoc "Runs one command and records a V5 Crucible transcript."
  use Mix.Task
  alias Trinity.Ops.Tasks

  @shortdoc "Runs a command with V5 transcript capture"
  @requirements ["app.start"]

  def run(argv), do: Tasks.run(:trinity_crucible_transcript, argv)
end
