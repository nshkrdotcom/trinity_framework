defmodule Mix.Tasks.Trinity.Sakana.RouterTrace do
  @moduledoc """
  Emits fixed-transcript Sakana router trace.
  """
  @shortdoc "Emit fixed-transcript Sakana router trace"
  use Mix.Task
  alias Trinity.Ops.Tasks

  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_sakana_router_trace, argv)
end
