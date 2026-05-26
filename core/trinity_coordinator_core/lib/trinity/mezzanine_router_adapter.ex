defmodule Trinity.MezzanineRouterAdapter do
  @moduledoc """
  Same-BEAM adapter from Mezzanine AI execution route requests into TRINITY.

  The module implements `Mezzanine.AIExecution.RouterAdapter` without moving
  Mezzanine workflow truth, context compilation, model invocation, or provider
  execution into TRINITY.
  """

  @behaviour Mezzanine.AIExecution.RouterAdapter

  alias Mezzanine.AIExecution.RouterAdapter
  alias OuterBrain.ContextABI.Failure
  alias Trinity.{Config, ProviderPool, Registry, Router, Validation}

  @impl true
  def route(route_request, opts \\ [])

  def route(route_request, opts) when is_map(route_request) and is_list(opts) do
    with :ok <- reject_raw(route_request),
         {:ok, tenant_ref} <- required(route_request, :tenant_ref),
         {:ok, workflow_ref} <- required(route_request, :workflow_ref),
         {:ok, context_packet_ref} <- required(route_request, :context_packet_ref),
         {:ok, packet_hash} <- required(route_request, :packet_hash),
         {:ok, authority_ref} <- required(route_request, :authority_ref),
         {:ok, route_policy_ref} <- required(route_request, :route_policy_ref),
         {:ok, trace_ref} <- required(route_request, :trace_ref),
         {:ok, model_classes} <- model_classes(route_request),
         {:ok, config} <- config(route_request, model_classes, opts),
         {:ok, decision} <-
           route_with_trinity(config, route_request, workflow_ref, trace_ref, opts),
         {:ok, role_pack} <- role_pack(config, decision.selected_role_ref),
         {:ok, provider_slot} <- provider_slot(config, decision.selected_role_ref) do
      {:ok,
       %{
         route_decision_ref: decision.router_decision_ref,
         context_packet_ref: context_packet_ref,
         packet_hash: packet_hash,
         selected_route_kind: :trinity_coordinated,
         selected_model_profile_ref: provider_slot.model_profile_ref,
         provider_or_runtime_ref: provider_slot.target_ref,
         provider_family: Atom.to_string(provider_slot.slot_kind),
         route_policy_ref: route_policy_ref,
         verifier_ref: role_pack.verifier_profile_ref,
         fallback_plan_ref: fallback_plan_ref(decision),
         cost_estimate: cost_estimate(role_pack, provider_slot),
         budget_status: :within_budget,
         authority_packet_ref: authority_ref,
         tenant_ref: tenant_ref,
         workflow_ref: workflow_ref,
         reason_codes: reason_codes(decision),
         trace_ref: trace_ref,
         trinity: %{
           router_artifact_ref: decision.router_artifact_ref,
           extractor_ref: decision.extractor_ref,
           head_ref: decision.head_ref,
           selected_role_ref: decision.selected_role_ref,
           confidence_band: decision.confidence_band,
           replay_ref: decision.replay_ref
         }
       }}
    end
  end

  def route(_route_request, _opts),
    do: failure("trinity.route.invalid_route_request.v1", "route request is invalid")

  defp reject_raw(attrs) do
    case Validation.reject_forbidden_raw_fields(attrs) do
      :ok ->
        :ok

      {:error, {:forbidden_raw_field, field}} ->
        failure(
          "trinity.route.raw_payload_rejected.v1",
          "route request cannot carry raw payloads",
          ["field://#{Atom.to_string(field)}"]
        )

      {:error, reason} ->
        failure("trinity.route.invalid_route_request.v1", "route request is invalid", [
          "reason://#{inspect(reason)}"
        ])
    end
  end

  defp required(attrs, field) do
    case Validation.require_binary(attrs, field) do
      {:ok, value} ->
        {:ok, value}

      {:error, reason} ->
        failure(
          "trinity.route.missing_route_ref.v1",
          "route request is missing a required ref",
          ["field://#{Atom.to_string(field)}", "reason://#{inspect(reason)}"]
        )
    end
  end

  defp model_classes(route_request) do
    case Map.get(route_request, :model_class_allowlist) ||
           Map.get(route_request, "model_class_allowlist", []) do
      [first | _rest] = values when is_binary(first) ->
        {:ok, values}

      _other ->
        failure(
          "trinity.route.missing_route_ref.v1",
          "route request is missing a model class allowlist",
          ["field://model_class_allowlist"]
        )
    end
  end

  defp config(route_request, model_profiles, opts) do
    with {:ok, config_attrs} <- config_attrs(route_request, model_profiles, opts) do
      case Config.compile(config_attrs) do
        {:ok, config} ->
          {:ok, config}

        {:error, reason} ->
          failure(
            "trinity.route.invalid_router_config.v1",
            "TRINITY router configuration is invalid",
            ["reason://#{inspect(reason)}"]
          )
      end
    end
  end

  defp config_attrs(route_request, model_profiles, opts) do
    case Keyword.fetch(opts, :trinity_config) do
      {:ok, config_attrs} -> {:ok, config_attrs}
      :error -> default_config(route_request, model_profiles, opts)
    end
  end

  defp route_with_trinity(config, route_request, workflow_ref, trace_ref, opts) do
    route_context = %{
      coordination_run_ref: workflow_ref,
      preferred_role_ref:
        Keyword.get(opts, :preferred_role_ref) || fetch(route_request, :preferred_role_ref),
      context_packet_ref: fetch(route_request, :context_packet_ref),
      packet_hash: fetch(route_request, :packet_hash),
      route_policy_ref: fetch(route_request, :route_policy_ref),
      authority_ref: fetch(route_request, :authority_ref),
      trace_ref: trace_ref,
      replay_ref: Keyword.get(opts, :replay_ref) || fetch(route_request, :replay_ref)
    }

    case Router.route(config, route_context) do
      {:ok, decision} ->
        {:ok, decision}

      {:error, reason} ->
        failure("trinity.route.no_route_available.v1", "TRINITY could not produce a route", [
          "reason://#{inspect(reason)}"
        ])
    end
  end

  defp role_pack(config, selected_role_ref) do
    case Registry.fetch_role_pack(config.registry, selected_role_ref) do
      {:ok, role_pack} ->
        {:ok, role_pack}

      {:error, reason} ->
        failure(
          "trinity.route.role_pack_missing.v1",
          "selected TRINITY role pack is unavailable",
          [
            "reason://#{inspect(reason)}"
          ]
        )
    end
  end

  defp provider_slot(config, selected_role_ref) do
    case ProviderPool.slot_for_role(config.provider_pool, selected_role_ref) do
      {:ok, provider_slot} ->
        {:ok, provider_slot}

      {:error, reason} ->
        failure(
          "trinity.route.provider_slot_missing.v1",
          "selected TRINITY role has no governed provider slot",
          ["reason://#{inspect(reason)}"]
        )
    end
  end

  defp default_config(route_request, model_classes, opts) do
    role_ref = Keyword.get(opts, :default_role_ref, "role://trinity/default")

    with {:ok, selected_model_profile_ref} <-
           selected_model_profile_ref(route_request, model_classes, opts) do
      {:ok,
       %{
         router_artifact: %{
           router_artifact_ref: "router-artifact://trinity/mezzanine/default",
           extractor_ref: "extractor://trinity/mezzanine/context-packet",
           head_ref: "router-head://trinity/mezzanine/default",
           compatibility_ref: "compatibility://trinity/mezzanine/router-adapter/v1",
           calibration_ref: "calibration://trinity/mezzanine/default",
           parity_ref: "parity://trinity/mezzanine/default",
           hash_ref: fetch(route_request, :packet_hash)
         },
         role_packs: [
           %{
             role_ref: role_ref,
             prompt_ref: "prompt://trinity/role/default",
             capability_refs: ["capability://trinity/route/default"],
             allowed_model_profile_refs: [selected_model_profile_ref],
             tool_policy_ref: "tool-policy://trinity/none",
             memory_profile_ref: "memory-profile://trinity/ref-only",
             guardrail_profile_ref: "guardrail-profile://trinity/default",
             verifier_profile_ref: "verifier-profile://trinity/default",
             budget_ref: fetch(route_request, :budget_ref) || "budget://trinity/default",
             context_budget_ref:
               fetch(route_request, :context_budget_ref) || "context-budget://trinity/default",
             handoff_policy_ref: "handoff-policy://trinity/default",
             projection_ref: "projection://trinity/mezzanine/default",
             gepa_target_refs: []
           }
         ],
         provider_pool: [
           %{
             slot_ref: "slot://trinity/default",
             slot_kind: :mock,
             role_refs: [role_ref],
             model_profile_ref: selected_model_profile_ref,
             endpoint_profile_ref: "endpoint-profile://trinity/default",
             operation_policy_ref: fetch(route_request, :route_policy_ref),
             target_ref: "runtime://trinity/default",
             credential_ref: "credential://trinity/ref-only",
             per_role_constraints: %{
               role_ref => %{
                 budget_ref: fetch(route_request, :budget_ref) || "budget://trinity/default"
               }
             }
           }
         ]
       }}
    end
  end

  defp selected_model_profile_ref(route_request, model_classes, opts) do
    class_ref = List.first(model_classes)
    profile_map = model_class_profile_map(route_request, opts)

    cond do
      is_map(profile_map) and profile_map[class_ref] ->
        {:ok, List.wrap(profile_map[class_ref]) |> List.first()}

      is_binary(class_ref) and String.starts_with?(class_ref, "model-profile://") ->
        {:ok, class_ref}

      true ->
        failure(
          "trinity.route.model_class_unmapped.v1",
          "model class has no concrete model profile mapping",
          [class_ref]
        )
    end
  end

  defp model_class_profile_map(route_request, opts) do
    Keyword.get(opts, :model_class_profile_map) ||
      fetch(route_request, :model_class_profile_map) ||
      %{
        "model-class://fixture" => ["model-profile://fixture/worker"],
        "class://coding-small" => ["model-profile://fixture/worker"]
      }
  end

  defp reason_codes(%{fallback_reason: nil, confidence_band: :high}),
    do: ["trinity.route.selected.v1"]

  defp reason_codes(%{fallback_reason: nil}),
    do: ["trinity.route.default_role.v1"]

  defp reason_codes(%{fallback_reason: fallback_reason}),
    do: ["trinity.route.fallback.#{fallback_reason}.v1"]

  defp fallback_plan_ref(%{fallback_reason: nil}), do: nil
  defp fallback_plan_ref(%{fallback_reason: reason}), do: "fallback-plan://trinity/#{reason}"

  defp cost_estimate(role_pack, provider_slot) do
    %{
      budget_ref: role_pack.budget_ref,
      model_profile_ref: provider_slot.model_profile_ref,
      estimate_ref: "cost-estimate://trinity/#{hash_suffix(provider_slot.slot_ref)}"
    }
  end

  defp hash_suffix(value) do
    :crypto.hash(:sha256, value)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  defp fetch(attrs, field), do: Map.get(attrs, field) || Map.get(attrs, Atom.to_string(field))

  defp failure(reason_code, safe_message, evidence_refs \\ []) do
    {:ok, failure} =
      Failure.new(%{
        owner: :trinity,
        reason_code: reason_code,
        safe_message: safe_message,
        evidence_refs: evidence_refs
      })

    {:error, failure}
  end

  @doc false
  @spec behaviour_contract() :: module()
  def behaviour_contract, do: RouterAdapter
end
