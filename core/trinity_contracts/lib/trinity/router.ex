defmodule Trinity.Router do
  @moduledoc """
  Ref-only TRINITY router.
  """

  alias Trinity.{Config, Extractor, RouterDecision, RouterHead, Validation}

  def route(%Config{} = config, context) when is_map(context) do
    with {:ok, coordination_run_ref} <- Validation.require_binary(context, :coordination_run_ref),
         {:ok, extractor_ref} <- Extractor.extract_ref(config.router_artifact, context),
         preferred_role_ref <- Validation.fetch(context, :preferred_role_ref),
         {:ok, role_pack, route_status} <-
           RouterHead.select_role(config.registry, preferred_role_ref),
         {:ok, trace_ref} <- Validation.optional_binary(context, :trace_ref),
         {:ok, replay_ref} <- Validation.optional_binary(context, :replay_ref) do
      {:ok,
       %RouterDecision{
         router_decision_ref: decision_ref(coordination_run_ref, role_pack.role_ref),
         coordination_run_ref: coordination_run_ref,
         router_artifact_ref: config.router_artifact.router_artifact_ref,
         extractor_ref: extractor_ref,
         head_ref: config.router_artifact.head_ref,
         selected_role_ref: role_pack.role_ref,
         confidence_band: confidence_band(route_status),
         fallback_reason: fallback_reason(route_status),
         trace_ref: trace_ref,
         replay_ref: replay_ref
       }}
    end
  end

  defp decision_ref(coordination_run_ref, selected_role_ref),
    do: "router_decision:" <> coordination_run_ref <> ":" <> selected_role_ref

  defp confidence_band(:selected), do: :high
  defp confidence_band(_route_status), do: :fallback

  defp fallback_reason(:invalid_route), do: :invalid_route
  defp fallback_reason(:default_route), do: nil
  defp fallback_reason(:selected), do: nil
end
