defmodule Mix.Tasks.Trinity.Crucible.TraceReplay do
  @moduledoc "Replays a Crucible trace through policy artifacts."
  @shortdoc "Replays a Crucible trace"

  use Mix.Task

  alias Trinity.Ops.Tasks

  @impl true
  def run(argv), do: Tasks.run(:trinity_crucible_trace_replay, argv)
end
