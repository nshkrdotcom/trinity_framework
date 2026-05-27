defmodule Mix.Tasks.Trinity.Crucible.MatrixEval do
  @moduledoc "Runs the Trinity Crucible route matrix evaluation."
  use Mix.Task
  alias Trinity.Ops.Tasks

  @shortdoc "Runs the Crucible route matrix eval"
  @requirements ["app.start"]

  def run(argv), do: Tasks.run(:trinity_crucible_matrix_eval, argv)
end
