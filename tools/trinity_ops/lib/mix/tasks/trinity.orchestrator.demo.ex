defmodule Mix.Tasks.Trinity.Orchestrator.Demo do
  @moduledoc """
  Runs an Orchestrator-backed TRINITY route and provider demo.
  """
  @shortdoc "Runs an Orchestrator-backed TRINITY demo"
  use Mix.Task

  alias Trinity.Ops.Tasks

  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_orchestrator_demo, argv)
end
