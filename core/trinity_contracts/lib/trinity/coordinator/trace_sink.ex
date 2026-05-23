defmodule Trinity.Coordinator.TraceSink do
  @moduledoc """
  Behaviour for coordinator trace/event sinks.
  """

  alias Trinity.Coordinator.TraceEvent

  @callback emit(TraceEvent.t(), keyword()) :: :ok | {:error, term()}
end
