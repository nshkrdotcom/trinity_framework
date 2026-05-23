defmodule Trinity.Coordinator.RouteDecision do
  @moduledoc """
  Runtime-side route decision with projection to the public `Trinity.RouterDecision`.
  """

  alias Trinity.Coordinator.RouteLogits
  alias Trinity.RouterDecision

  @enforce_keys [
    :router_decision_ref,
    :coordination_run_ref,
    :router_artifact_ref,
    :extractor_ref,
    :head_ref,
    :selected_role_ref,
    :confidence_band,
    :selected_role_id,
    :selected_agent_id
  ]
  defstruct [
    :router_decision_ref,
    :coordination_run_ref,
    :router_artifact_ref,
    :extractor_ref,
    :head_ref,
    :selected_role_ref,
    :confidence_band,
    :fallback_reason,
    :trace_ref,
    :replay_ref,
    :selected_role_id,
    :selected_agent_id,
    :role_name,
    :token_count,
    :transcript_hash,
    :route_hash,
    :route_hash_inputs,
    :role_logits,
    :agent_logits,
    :backend_label,
    :runtime_profile,
    :margins,
    :artifact_identity,
    metadata: %{}
  ]

  @type t :: %__MODULE__{}

  @spec from_logits(RouteLogits.t(), keyword() | map()) :: {:ok, t()} | {:error, term()}
  def from_logits(%RouteLogits{} = logits, attrs) when is_list(attrs) or is_map(attrs) do
    attrs = if is_list(attrs), do: Map.new(attrs), else: attrs

    with {:ok, router_decision_ref} <- require_binary(attrs, :router_decision_ref),
         {:ok, coordination_run_ref} <- require_binary(attrs, :coordination_run_ref),
         {:ok, router_artifact_ref} <- require_binary(attrs, :router_artifact_ref),
         {:ok, extractor_ref} <- require_binary(attrs, :extractor_ref),
         {:ok, head_ref} <- require_binary(attrs, :head_ref),
         {:ok, selected_role_ref} <- require_binary(attrs, :selected_role_ref),
         {:ok, confidence_band} <- require_atom(attrs, :confidence_band) do
      {:ok,
       %__MODULE__{
         router_decision_ref: router_decision_ref,
         coordination_run_ref: coordination_run_ref,
         router_artifact_ref: router_artifact_ref,
         extractor_ref: extractor_ref,
         head_ref: head_ref,
         selected_role_ref: selected_role_ref,
         confidence_band: confidence_band,
         fallback_reason: fetch(attrs, :fallback_reason),
         trace_ref: fetch(attrs, :trace_ref),
         replay_ref: fetch(attrs, :replay_ref),
         selected_role_id: logits.selected_role_id,
         selected_agent_id: logits.selected_agent_id,
         role_name: fetch(attrs, :role_name),
         token_count: logits.token_count,
         transcript_hash: logits.transcript_hash,
         route_hash: fetch(attrs, :route_hash),
         route_hash_inputs: logits.route_hash_inputs,
         role_logits: logits.role_logits,
         agent_logits: logits.agent_logits,
         backend_label: logits.backend_label,
         runtime_profile: logits.runtime_profile,
         margins: logits.margins,
         artifact_identity: fetch(attrs, :artifact_identity),
         metadata: fetch(attrs, :metadata, %{})
       }}
    end
  end

  @spec from_logits!(RouteLogits.t(), keyword() | map()) :: t()
  def from_logits!(%RouteLogits{} = logits, attrs) do
    case from_logits(logits, attrs) do
      {:ok, decision} -> decision
      {:error, reason} -> raise ArgumentError, "invalid route decision: #{inspect(reason)}"
    end
  end

  @spec to_router_decision(t()) :: RouterDecision.t()
  def to_router_decision(%__MODULE__{} = decision) do
    %RouterDecision{
      router_decision_ref: decision.router_decision_ref,
      coordination_run_ref: decision.coordination_run_ref,
      router_artifact_ref: decision.router_artifact_ref,
      extractor_ref: decision.extractor_ref,
      head_ref: decision.head_ref,
      selected_role_ref: decision.selected_role_ref,
      confidence_band: decision.confidence_band,
      fallback_reason: decision.fallback_reason,
      trace_ref: decision.trace_ref,
      replay_ref: decision.replay_ref
    }
  end

  defp require_binary(attrs, field) do
    case fetch(attrs, field) do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: {:error, {:blank_field, field}}, else: {:ok, value}

      value ->
        {:error, {:invalid_binary_field, field, value}}
    end
  end

  defp require_atom(attrs, field) do
    case fetch(attrs, field) do
      value when is_atom(value) -> {:ok, value}
      value -> {:error, {:invalid_atom_field, field, value}}
    end
  end

  defp fetch(attrs, field, default \\ nil),
    do: Map.get(attrs, field, Map.get(attrs, Atom.to_string(field), default))
end
