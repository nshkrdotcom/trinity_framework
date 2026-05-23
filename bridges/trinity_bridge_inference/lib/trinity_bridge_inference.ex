defmodule Trinity.Bridge.Inference do
  @moduledoc """
  Mapping routed TRINITY agent calls to the shared provider/inference layer.
  """

  alias Trinity.Bridge.Inference.AgentCaller

  @doc "Dispatches a routed coordinator intent through the provider inference bridge."
  defdelegate call(intent, opts \\ []), to: AgentCaller
end
