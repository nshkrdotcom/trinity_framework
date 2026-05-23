defmodule Mix.Tasks.Trinity.Sakana.ImportPython do
  @moduledoc """
  Imports Python semantic Sakana artifacts.
  """
  @shortdoc "Imports Python semantic Sakana artifacts"
  use Mix.Task
  alias Trinity.Ops.Tasks

  @impl Mix.Task
  def run(argv), do: Tasks.run(:trinity_sakana_import_python, argv)
end
