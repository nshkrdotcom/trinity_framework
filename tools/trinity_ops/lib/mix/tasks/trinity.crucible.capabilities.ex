defmodule Mix.Tasks.Trinity.Crucible.Capabilities do
  @moduledoc "Summarizes Crucible capabilities from a checked-in or operator-supplied trace."
  use Mix.Task
  alias Trinity.Ops.Tasks

  @shortdoc "Summarizes Crucible trace capabilities"
  @requirements ["app.start"]

  def run(argv), do: Tasks.run(:trinity_crucible_capabilities, argv)
end
