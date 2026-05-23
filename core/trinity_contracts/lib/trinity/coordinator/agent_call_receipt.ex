defmodule Trinity.Coordinator.AgentCallReceipt do
  @moduledoc """
  Provider call receipt returned to coordinator core.
  """

  @enforce_keys [:intent_ref, :status]
  defstruct [
    :intent_ref,
    :status,
    :response_ref,
    :finish_reason,
    :trace_ref,
    usage: %{},
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          intent_ref: String.t(),
          status: :ok | :error | atom(),
          response_ref: String.t() | nil,
          finish_reason: atom() | String.t() | nil,
          trace_ref: String.t() | nil,
          usage: map(),
          metadata: map()
        }
end
