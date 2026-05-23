defmodule Mix.Tasks.Trinity.Gates do
  @moduledoc """
  Runs the TRINITY quality gate matrix.
  """
  @shortdoc "Runs the TRINITY quality gate matrix"
  use Mix.Task
  alias Trinity.Ops.Tasks

  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_gates, argv)
end
