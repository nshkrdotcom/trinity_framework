defmodule Trinity.Coordinator.ModelRuntime do
  @moduledoc """
  Behaviour for model runtimes that keep hidden-state extraction internal.
  """

  alias Trinity.Coordinator.{HiddenStateExtractionPlan, RouteLogits}

  @callback load(HiddenStateExtractionPlan.t(), keyword()) :: {:ok, term()} | {:error, term()}
  @callback route(term(), HiddenStateExtractionPlan.t(), keyword()) ::
              {:ok, RouteLogits.t()} | {:error, term()}
end
