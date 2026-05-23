defmodule Mix.Tasks.Trinity.Sakana.LargeTensorChunks do
  @moduledoc """
  Replays embedding/LM-head Sakana stages in row chunks.
  """
  @shortdoc "Replays embedding/LM-head Sakana stages in row chunks"
  use Mix.Task
  alias Trinity.Ops.Tasks

  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_sakana_large_tensor_chunks, argv)
end
