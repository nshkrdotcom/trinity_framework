defmodule Trinity.Crucible.DecisionAdapter do
  @moduledoc """
  Deterministic adapter from Crucible policy decisions to Trinity route decisions.
  """

  alias CruciblePolicy.RouteDecision, as: CrucibleRouteDecision
  alias Trinity.Coordinator.{RoleInjector, RouteDecision, RouteLogits}
  alias Trinity.Crucible.RequestContext

  @default_agent_by_role %{worker: 0, thinker: 1, verifier: 2, unknown: 0}

  @spec adapt(CrucibleRouteDecision.t(), keyword() | map()) ::
          {:ok, RouteDecision.t()} | {:error, term()}
  def adapt(decision, attrs \\ [])

  def adapt(%CrucibleRouteDecision{} = crucible_decision, attrs) do
    attrs = attrs_map(attrs)
    context = request_context(field(attrs, :request_context))
    decision = crucible_decision.decision
    selected_target = normalize_target(crucible_decision.selected_target)
    confidence = decision && decision.confidence

    logits = route_logits(crucible_decision, selected_target, attrs, context, confidence)
    route_attrs = route_attrs(crucible_decision, selected_target, attrs, context, logits)

    RouteDecision.from_logits(logits, route_attrs)
  end

  def adapt(_decision, _attrs), do: {:error, :invalid_crucible_route_decision}

  @spec adapt!(CrucibleRouteDecision.t(), keyword() | map()) :: RouteDecision.t()
  def adapt!(%CrucibleRouteDecision{} = decision, attrs \\ []) do
    case adapt(decision, attrs) do
      {:ok, route_decision} -> route_decision
      {:error, reason} -> raise ArgumentError, "invalid Crucible decision: #{inspect(reason)}"
    end
  end

  @spec confidence_band(number() | nil) :: :high | :medium | :low | :unknown
  def confidence_band(confidence) when is_number(confidence) do
    cond do
      confidence >= 0.8 -> :high
      confidence >= 0.5 -> :medium
      true -> :low
    end
  end

  def confidence_band(_confidence), do: :unknown

  defp selected_role_id(%CrucibleRouteDecision{} = decision, target, attrs) do
    field(attrs, :selected_role_id) ||
      field(decision.metadata, :selected_role_id) ||
      RoleInjector.role_id(target) ||
      0
  end

  defp selected_agent_id(%CrucibleRouteDecision{} = decision, target, attrs) do
    field(attrs, :selected_agent_id) ||
      field(attrs, :agent_id) ||
      field(decision.metadata, :selected_agent_id) ||
      role_agent_id(field(attrs, :runtime_profile), target) ||
      Map.fetch!(@default_agent_by_role, target)
  end

  defp role_agent_id(runtime_profile, target) when is_map(runtime_profile) do
    runtime_profile
    |> field(:agent_slot_by_role, %{})
    |> field(target)
  end

  defp role_agent_id(_runtime_profile, _target), do: nil

  defp request_context(%RequestContext{} = context), do: context
  defp request_context(attrs) when is_list(attrs) or is_map(attrs), do: RequestContext.new(attrs)
  defp request_context(_attrs), do: nil

  defp normalize_target(target) when target in [:worker, :thinker, :verifier], do: target
  defp normalize_target(target) when is_integer(target), do: RoleInjector.role_atom(target)
  defp normalize_target(target) when is_binary(target), do: RoleInjector.role_atom(target)
  defp normalize_target(_target), do: :unknown

  defp route_logits(%CrucibleRouteDecision{} = decision, target, attrs, context, confidence) do
    role_id = selected_role_id(decision, target, attrs)
    agent_id = selected_agent_id(decision, target, attrs)

    %RouteLogits{
      role_logits: nil,
      agent_logits: nil,
      selected_role_id: role_id,
      selected_agent_id: agent_id,
      token_count: field(attrs, :token_count, 0),
      transcript_hash:
        transcript_hash(field(attrs, :messages_or_hash), field(attrs, :transcript_hash)),
      route_hash_inputs: route_hash_inputs(decision, role_id, agent_id),
      backend_label: :crucible_policy,
      runtime_profile: runtime_profile_name(attrs, context),
      margins: %{policy_confidence: confidence}
    }
  end

  defp route_attrs(%CrucibleRouteDecision{} = decision, target, attrs, context, logits) do
    policy_decision = decision.decision
    trace_id = policy_decision && policy_decision.trace_id
    confidence = policy_decision && policy_decision.confidence

    %{
      router_decision_ref:
        route_attr(attrs, :router_decision_ref, decision_ref(policy_decision, trace_id)),
      coordination_run_ref: coordination_run_ref(attrs, context, trace_id),
      router_artifact_ref: router_artifact_ref(attrs, policy_decision),
      extractor_ref: extractor_ref(attrs, trace_id),
      head_ref: head_ref(attrs, policy_decision),
      selected_role_ref: route_attr(attrs, :selected_role_ref, "role:#{target}"),
      confidence_band: route_attr(attrs, :confidence_band, confidence_band(confidence)),
      trace_ref: route_attr(attrs, :trace_ref, trace_id),
      replay_ref: field(attrs, :replay_ref),
      role_name: route_attr(attrs, :role_name, RoleInjector.role_name(target)),
      route_hash: route_attr(attrs, :route_hash, hash_term(logits.route_hash_inputs)),
      artifact_identity: route_attr(attrs, :artifact_identity, decision.selected_model),
      metadata: metadata(decision, attrs, context)
    }
  end

  defp route_attr(attrs, key, fallback), do: field(attrs, key) || fallback

  defp route_hash_inputs(%CrucibleRouteDecision{} = decision, role_id, agent_id) do
    %{
      adapter: "trinity.crucible.decision_adapter.v1",
      selected_target: normalize_target(decision.selected_target),
      selected_model: inspect(decision.selected_model),
      selected_role_id: role_id,
      selected_agent_id: agent_id,
      trace_id: decision.decision && decision.decision.trace_id,
      policy_ref: decision.decision && decision.decision.policy_ref
    }
  end

  defp decision_ref(%{decision_id: decision_id}, _trace_id)
       when is_binary(decision_id) and decision_id != "",
       do: decision_id

  defp decision_ref(_decision, trace_id) when is_binary(trace_id),
    do: "trinity:crucible:route-decision:#{hash_term(trace_id)}"

  defp decision_ref(_decision, _trace_id), do: "trinity:crucible:route-decision:unknown"

  defp coordination_run_ref(attrs, %RequestContext{coordination_run_ref: ref}, _trace_id)
       when is_binary(ref),
       do: field(attrs, :coordination_run_ref) || ref

  defp coordination_run_ref(attrs, _context, trace_id),
    do: field(attrs, :coordination_run_ref) || "coordination-run:crucible:#{hash_term(trace_id)}"

  defp router_artifact_ref(attrs, decision) do
    field(attrs, :router_artifact_ref) ||
      "crucible_policy:#{safe_ref(decision && decision.policy_ref)}"
  end

  defp extractor_ref(attrs, trace_id),
    do: field(attrs, :extractor_ref) || "crucible_trace:#{safe_ref(trace_id)}"

  defp head_ref(attrs, decision),
    do:
      field(attrs, :head_ref) ||
        "crucible_policy_plan:#{safe_ref(decision && decision.policy_ref)}"

  defp runtime_profile_name(attrs, %RequestContext{runtime_profile: profile}) do
    field(attrs, :runtime_profile) || profile || :crucible
  end

  defp runtime_profile_name(attrs, _context), do: field(attrs, :runtime_profile, :crucible)

  defp metadata(%CrucibleRouteDecision{} = decision, attrs, context) do
    attrs_metadata = field(attrs, :metadata, %{})
    policy_decision = decision.decision

    Map.merge(attrs_metadata, %{
      crucible_adapter: :decision_adapter_v1,
      crucible_decision_id: policy_decision && policy_decision.decision_id,
      crucible_policy_ref: policy_decision && policy_decision.policy_ref,
      crucible_evidence_refs: (policy_decision && policy_decision.evidence_refs) || [],
      crucible_uncertainty: policy_decision && policy_decision.uncertainty,
      crucible_selected_target: normalize_target(decision.selected_target),
      task_type: context && context.task_type
    })
  end

  defp transcript_hash(nil, nil), do: hash_term([])
  defp transcript_hash(nil, fallback) when is_binary(fallback), do: fallback
  defp transcript_hash(hash, _fallback) when is_binary(hash), do: hash
  defp transcript_hash(messages, _fallback) when is_list(messages), do: hash_term(messages)
  defp transcript_hash(value, _fallback), do: hash_term(value)

  defp safe_ref(nil), do: "unknown"

  defp safe_ref(value) do
    value
    |> to_string()
    |> String.graphemes()
    |> Enum.map_join(fn char ->
      if safe_ref_char?(char), do: char, else: "_"
    end)
    |> collapse_underscores()
  end

  defp safe_ref_char?(<<char::utf8>>) do
    ascii_letter?(char) or ascii_digit?(char) or char in [45, 46, 58, 95]
  end

  defp safe_ref_char?(_char), do: false

  defp ascii_letter?(char), do: char in ?A..?Z or char in ?a..?z
  defp ascii_digit?(char), do: char in ?0..?9

  defp collapse_underscores(value), do: collapse_underscores(value, "", false)

  defp collapse_underscores("", acc, _previous?), do: acc

  defp collapse_underscores("_" <> rest, acc, true), do: collapse_underscores(rest, acc, true)

  defp collapse_underscores("_" <> rest, acc, false),
    do: collapse_underscores(rest, acc <> "_", true)

  defp collapse_underscores(<<char::utf8, rest::binary>>, acc, _previous?),
    do: collapse_underscores(rest, acc <> <<char::utf8>>, false)

  defp attrs_map(attrs) when is_list(attrs), do: Map.new(attrs)
  defp attrs_map(attrs) when is_map(attrs), do: attrs

  defp field(value, field, default \\ nil)

  defp field(nil, _field, default), do: default

  defp field(map, field, default) when is_map(map),
    do: Map.get(map, field, Map.get(map, Atom.to_string(field), default))

  defp field(_value, _field, default), do: default

  defp hash_term(value) do
    value
    |> normalize_for_hash()
    |> :erlang.term_to_binary([:compressed])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp normalize_for_hash(%_{} = struct), do: struct |> Map.from_struct() |> normalize_for_hash()

  defp normalize_for_hash(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested} -> {normalize_key(key), normalize_for_hash(nested)} end)
    |> Enum.sort_by(fn {key, _value} -> key end)
  end

  defp normalize_for_hash(value) when is_list(value), do: Enum.map(value, &normalize_for_hash/1)

  defp normalize_for_hash(value) when is_tuple(value),
    do: value |> Tuple.to_list() |> normalize_for_hash()

  defp normalize_for_hash(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_for_hash(value), do: value

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: inspect(key)
end
