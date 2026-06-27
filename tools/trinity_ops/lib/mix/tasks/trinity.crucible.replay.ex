defmodule Mix.Tasks.Trinity.Crucible.Replay do
  @moduledoc "Replays a Crucible trace through validation and deterministic policy evaluation."
  use Mix.Task
  alias Trinity.Ops.Tasks

  @shortdoc "Replays a Crucible trace"
  @requirements ["app.start"]

  def run(argv), do: Tasks.run(:trinity_crucible_replay, argv)
end
