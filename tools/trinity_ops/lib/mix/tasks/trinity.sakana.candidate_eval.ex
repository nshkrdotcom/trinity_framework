defmodule Mix.Tasks.Trinity.Sakana.CandidateEval do
  @moduledoc "Evaluates non-mutating Sakana router candidate proposals."
  @shortdoc "Evaluates Sakana candidate routes or vectors"
  use Mix.Task

  alias Trinity.Ops.Tasks

  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_sakana_candidate_eval, argv)
end
