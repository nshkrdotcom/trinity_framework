defmodule Trinity.Coordinator.ModelRuntime do
  @moduledoc """
  Behaviour for model runtimes that keep model-internal signal work internal.
  """

  alias Trinity.Coordinator.{HiddenStateExtractionPlan, RouteLogits}

  @type routing_plan :: HiddenStateExtractionPlan.t() | CrucibleTap.TapPlan.t()
  @type route_result :: RouteLogits.t() | CruciblePolicy.RouteDecision.t()

  @callback load(routing_plan(), keyword()) :: {:ok, term()} | {:error, term()}
  @callback route(term(), routing_plan(), keyword()) :: {:ok, route_result()} | {:error, term()}
end
