defmodule Trinity.Coordinator.RouteLogits do
  @moduledoc """
  Small route-head output returned by model runtimes.
  """

  @enforce_keys [
    :role_logits,
    :agent_logits,
    :selected_role_id,
    :selected_agent_id,
    :token_count,
    :transcript_hash,
    :route_hash_inputs,
    :backend_label,
    :runtime_profile,
    :margins
  ]
  defstruct [
    :role_logits,
    :agent_logits,
    :selected_role_id,
    :selected_agent_id,
    :token_count,
    :transcript_hash,
    :route_hash_inputs,
    :backend_label,
    :runtime_profile,
    :margins
  ]

  @type t :: %__MODULE__{
          role_logits: [number()] | term(),
          agent_logits: [number()] | term(),
          selected_role_id: non_neg_integer(),
          selected_agent_id: non_neg_integer(),
          token_count: non_neg_integer(),
          transcript_hash: String.t(),
          route_hash_inputs: map(),
          backend_label: term(),
          runtime_profile: atom() | String.t(),
          margins: %{optional(atom()) => number()}
        }
end
