defmodule Trinity.Coordinator.TraceEvent do
  @moduledoc """
  Typed coordinator event for trace sinks.
  """

  @enforce_keys [:event_ref, :event_type]
  defstruct [
    :event_ref,
    :event_type,
    :trace_ref,
    :coordination_run_ref,
    :timestamp_ms,
    payload: %{},
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          event_ref: String.t(),
          event_type: atom() | String.t(),
          trace_ref: String.t() | nil,
          coordination_run_ref: String.t() | nil,
          timestamp_ms: integer() | nil,
          payload: map(),
          metadata: map()
        }
end
