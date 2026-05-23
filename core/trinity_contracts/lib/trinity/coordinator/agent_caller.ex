defmodule Trinity.Coordinator.AgentCaller do
  @moduledoc """
  Behaviour for provider bridges invoked by coordinator core.
  """

  alias Trinity.Coordinator.{AgentCallIntent, AgentCallReceipt}

  @callback call(AgentCallIntent.t(), keyword()) :: {:ok, AgentCallReceipt.t()} | {:error, term()}
end
