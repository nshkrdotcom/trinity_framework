defmodule Mix.Tasks.Trinity.Demo do
  @moduledoc """
  Runs the active adapted-coordinator route demo.
  """
  @shortdoc "Runs the active adapted-coordinator route demo"
  use Mix.Task
  alias Trinity.Ops.Tasks

  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_demo, argv)
end
