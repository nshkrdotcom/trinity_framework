defmodule Mix.Tasks.Trinity.Sakana.ExportAdapted do
  @moduledoc """
  Exports Sakana-adapted Qwen tensors and router head.
  """
  @shortdoc "Exports Sakana-adapted Qwen tensors and router head"
  use Mix.Task
  alias Trinity.Ops.Tasks

  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_sakana_export_adapted, argv)
end
