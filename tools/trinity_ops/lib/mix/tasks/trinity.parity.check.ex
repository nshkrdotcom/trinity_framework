defmodule Mix.Tasks.Trinity.Parity.Check do
  @moduledoc """
  Wraps the Sakana parity comparator.
  """
  @shortdoc "Wraps the Sakana parity comparator"
  use Mix.Task
  alias Trinity.Ops.Tasks

  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_parity_check, argv)
end
