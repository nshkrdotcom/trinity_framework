defmodule Mix.Tasks.Trinity.Env.Check do
  @moduledoc """
  Validates the TRINITY build/runtime environment.
  """
  @shortdoc "Validates the TRINITY build/runtime environment"
  use Mix.Task
  alias Trinity.Ops.Tasks

  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_env_check, argv)
end
