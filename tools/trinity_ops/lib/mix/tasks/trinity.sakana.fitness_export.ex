defmodule Mix.Tasks.Trinity.Sakana.FitnessExport do
  @moduledoc """
  Exports deterministic Sakana fitness examples from TRINITY trace JSONL.
  """
  @shortdoc "Exports Sakana fitness JSONL from TRINITY traces"
  use Mix.Task

  alias Trinity.Ops.Tasks

  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_sakana_fitness_export, argv)
end
