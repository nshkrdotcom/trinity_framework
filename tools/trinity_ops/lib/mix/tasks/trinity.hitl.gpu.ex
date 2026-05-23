defmodule Mix.Tasks.Trinity.Hitl.Gpu do
  @moduledoc """
  Runs the HITL GPU/EXLA CUDA visibility check.
  """
  @shortdoc "HITL GPU/EXLA CUDA visibility check"
  use Mix.Task
  alias Trinity.Ops.Tasks

  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_hitl_gpu, argv)
end
