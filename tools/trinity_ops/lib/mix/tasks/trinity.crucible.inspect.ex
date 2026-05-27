defmodule Mix.Tasks.Trinity.Crucible.Inspect do
  @moduledoc "Inspects one Trinity Crucible route request."
  use Mix.Task
  alias Trinity.Ops.Tasks

  @shortdoc "Inspects a Crucible route request"
  @requirements ["app.start"]

  def run(argv), do: Tasks.run(:trinity_crucible_inspect, argv)
end
