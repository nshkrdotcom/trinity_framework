defmodule Mix.Tasks.Trinity.Hitl.HeadRoute do
  @moduledoc """
  Runs the HITL hidden-state to Sakana-head routing check.
  """
  @shortdoc "HITL hidden-state to Sakana-head routing check"
  use Mix.Task
  alias Trinity.Ops.Tasks

  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_hitl_head_route, argv)
end
