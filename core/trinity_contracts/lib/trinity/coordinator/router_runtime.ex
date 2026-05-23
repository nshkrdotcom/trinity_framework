defmodule Trinity.Coordinator.RouterRuntime do
  @moduledoc """
  Behaviour for turning route logits into runtime route decisions.
  """

  alias Trinity.Coordinator.{RouteDecision, RouteLogits}

  @callback decide(RouteLogits.t(), keyword()) :: {:ok, RouteDecision.t()} | {:error, term()}
end
