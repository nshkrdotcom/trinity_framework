defmodule Trinity.RouterDecision do
  @moduledoc """
  Router decision projection without raw prompt or provider payload fields.
  """

  @enforce_keys [
    :router_decision_ref,
    :coordination_run_ref,
    :router_artifact_ref,
    :extractor_ref,
    :head_ref,
    :selected_role_ref,
    :confidence_band
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
    :replay_ref
  ]

  @type t :: %__MODULE__{}

  def to_projection(%__MODULE__{} = decision) do
    %{
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
end
