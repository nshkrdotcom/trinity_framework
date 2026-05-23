defmodule Mix.Tasks.Trinity.Hitl.BaseQwen do
  @moduledoc """
  Runs the HITL base Qwen hidden-state check.
  """
  @shortdoc "HITL base Qwen hidden-state check"
  use Mix.Task
  alias Trinity.Ops.Tasks

  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_hitl_base_qwen, argv)
end
