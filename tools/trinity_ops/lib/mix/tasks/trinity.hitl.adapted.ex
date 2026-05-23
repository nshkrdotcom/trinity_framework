defmodule Mix.Tasks.Trinity.Hitl.Adapted do
  @moduledoc """
  Runs the HITL adapted-Qwen coordinator route check.
  """
  @shortdoc "HITL adapted-Qwen coordinator route check"
  use Mix.Task
  alias Trinity.Ops.Tasks

  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_hitl_adapted, argv)
end
