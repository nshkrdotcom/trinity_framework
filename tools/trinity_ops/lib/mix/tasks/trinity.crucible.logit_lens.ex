defmodule Mix.Tasks.Trinity.Crucible.LogitLens do
  @moduledoc "Runs a local tiny-model Crucible logit-lens report."
  @shortdoc "Runs a local Crucible logit-lens report"

  use Mix.Task

  alias Trinity.Ops.Tasks

  @impl true
  def run(argv), do: Tasks.run(:trinity_crucible_logit_lens, argv)
end
