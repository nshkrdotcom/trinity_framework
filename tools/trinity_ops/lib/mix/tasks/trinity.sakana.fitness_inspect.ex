defmodule Mix.Tasks.Trinity.Sakana.FitnessInspect do
  @moduledoc "Inspects exported Sakana fitness JSONL and manifest health."
  @shortdoc "Inspects Sakana fitness dataset health"
  use Mix.Task

  alias Trinity.Ops.Tasks

  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_sakana_fitness_inspect, argv)
end
