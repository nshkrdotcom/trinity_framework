defmodule Trinity.SingleNode do
  @moduledoc """
  The default single-node monolith composition package.
  """

  alias Trinity.SingleNode.RuntimeSupervisor

  defdelegate acquire_lease(opts \\ []), to: RuntimeSupervisor
  defdelegate dispatch(decision_or_route, messages, opts \\ []), to: RuntimeSupervisor
  defdelegate extraction_plan(messages, opts \\ []), to: RuntimeSupervisor
  defdelegate load_runtime(opts \\ []), to: RuntimeSupervisor
  defdelegate route(messages, opts \\ []), to: RuntimeSupervisor
end
