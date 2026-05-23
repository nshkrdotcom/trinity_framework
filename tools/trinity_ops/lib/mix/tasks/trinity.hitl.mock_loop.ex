defmodule Mix.Tasks.Trinity.Hitl.MockLoop do
  @moduledoc """
  Runs the HITL adapted coordinator mock-orchestrator check.
  """
  @shortdoc "HITL adapted coordinator mock-orchestrator check"
  use Mix.Task
  alias Trinity.Ops.Tasks

  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_hitl_mock_loop, argv)
end
