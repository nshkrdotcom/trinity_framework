defmodule Trinity.Coordinator.AgentCallIntent do
  @moduledoc """
  Provider call request emitted by coordinator core.
  """

  @enforce_keys [:intent_ref, :role_ref, :messages]
  defstruct [
    :intent_ref,
    :role_ref,
    :agent_ref,
    :provider_slot_ref,
    :model_profile_ref,
    :operation_policy_ref,
    :trace_ref,
    messages: [],
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          intent_ref: String.t(),
          role_ref: String.t(),
          agent_ref: String.t() | nil,
          provider_slot_ref: String.t() | nil,
          model_profile_ref: String.t() | nil,
          operation_policy_ref: String.t() | nil,
          trace_ref: String.t() | nil,
          messages: [map()],
          metadata: map()
        }
end
