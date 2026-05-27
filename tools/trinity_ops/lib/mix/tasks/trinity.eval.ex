defmodule Mix.Tasks.Trinity.Eval do
  @moduledoc "Runs Trinity evaluation suites through the framework task surface."
  use Mix.Task
  alias Trinity.Ops.Tasks

  @shortdoc "Runs a Trinity eval"
  @requirements ["app.start"]

  def run(argv), do: Tasks.run(:trinity_eval, argv)
end
