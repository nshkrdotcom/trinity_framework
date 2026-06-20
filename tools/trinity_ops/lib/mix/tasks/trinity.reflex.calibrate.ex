defmodule Mix.Tasks.Trinity.Reflex.Calibrate do
  @moduledoc "Calibrates router reflex thresholds over fitness examples."
  @shortdoc "Calibrates TRINITY router reflex thresholds"
  use Mix.Task

  alias Trinity.Ops.Tasks

  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_reflex_calibrate, argv)
end
