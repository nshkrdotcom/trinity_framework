defmodule Mix.Tasks.Trinity.Route.Demo do
  @moduledoc """
  Runs a gated adapted-coordinator route demo.
  """
  @shortdoc "Runs a gated adapted-coordinator route demo"
  use Mix.Task
  alias Trinity.Ops.Tasks

  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_route_demo, argv)
end
