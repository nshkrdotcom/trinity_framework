defmodule Mix.Tasks.Trinity.Sakana.FitnessReplay do
  @moduledoc "Replays score-v1 over exported Sakana fitness examples."
  @shortdoc "Replays Sakana fitness scores"
  use Mix.Task

  alias Trinity.Ops.Tasks

  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_sakana_fitness_replay, argv)
end
