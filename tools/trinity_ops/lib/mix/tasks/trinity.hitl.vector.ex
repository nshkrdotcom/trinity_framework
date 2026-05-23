defmodule Mix.Tasks.Trinity.Hitl.Vector do
  @moduledoc """
  Runs the HITL Sakana router-vector split check.
  """
  @shortdoc "HITL Sakana router-vector split check"
  use Mix.Task
  alias Trinity.Ops.Tasks

  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_hitl_vector, argv)
end
