defmodule Mix.Tasks.Trinity.Sakana.ParitySample do
  @moduledoc """
  Emits Sakana SVD sample parity diagnostics.
  """
  @shortdoc "Emits Sakana SVD sample parity diagnostics"
  use Mix.Task
  alias Trinity.Ops.Tasks

  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_sakana_parity_sample, argv)
end
