defmodule Trinity.Coordinator.RouteDecisionDerivation do
  @moduledoc """
  Derives `Trinity.Coordinator.RouteDecision` values from route logits.
  """

  alias CruciblePolicy.RouteDecision, as: CrucibleRouteDecision
  alias Trinity.Coordinator.{RoleInjector, RouteDecision, RouteLogits}

  @spec from_logits(RouteLogits.t(), [map()] | String.t() | nil, keyword() | map()) ::
          {:ok, RouteDecision.t()} | {:error, term()}
  def from_logits(%RouteLogits{} = logits, messages_or_hash \\ nil, attrs \\ []) do
    attrs = attrs_map(attrs)
    transcript_hash = transcript_hash(messages_or_hash, logits.transcript_hash)
    route_hash_inputs = logits.route_hash_inputs || %{}

    RouteDecision.from_logits(%{logits | transcript_hash: transcript_hash}, %{
      router_decision_ref: fetch(attrs, :router_decision_ref, generated_ref("route-decision")),
      coordination_run_ref:
        fetch(attrs, :coordination_run_ref, generated_ref("coordination-run")),
      router_artifact_ref: fetch(attrs, :router_artifact_ref, "router-artifact:unknown"),
      extractor_ref: fetch(attrs, :extractor_ref, "extractor:unknown"),
      head_ref: fetch(attrs, :head_ref, "head:unknown"),
      selected_role_ref: fetch(attrs, :selected_role_ref, "role:#{logits.selected_role_id}"),
      confidence_band: fetch(attrs, :confidence_band, confidence_band(logits.margins)),
      trace_ref: fetch(attrs, :trace_ref),
      replay_ref: fetch(attrs, :replay_ref),
      role_name: fetch(attrs, :role_name, RoleInjector.role_name(logits.selected_role_id)),
      route_hash: fetch(attrs, :route_hash, hash_term(route_hash_inputs)),
      artifact_identity: fetch(attrs, :artifact_identity),
      metadata: fetch(attrs, :metadata, %{})
    })
  end

  @spec from_crucible(CrucibleRouteDecision.t(), [map()] | String.t() | nil, keyword() | map()) ::
          {:ok, RouteDecision.t()} | {:error, term()}
  def from_crucible(
        %CrucibleRouteDecision{} = crucible_decision,
        messages_or_hash \\ nil,
        attrs \\ []
      ) do
    attrs = attrs_map(attrs)
    decision = crucible_decision.decision
    role_name = RoleInjector.role_name(crucible_decision.selected_target)
    selected_role_id = RoleInjector.role_id(role_name) || 0
    selected_agent_id = fetch(attrs, :selected_agent_id, fetch(attrs, :agent_id, 0))
    trace_id = decision && decision.trace_id

    logits = %RouteLogits{
      role_logits: nil,
      agent_logits: nil,
      selected_role_id: selected_role_id,
      selected_agent_id: selected_agent_id,
      token_count: 0,
      transcript_hash: transcript_hash(messages_or_hash, nil),
      route_hash_inputs: %{
        "selected_target" => Atom.to_string(crucible_decision.selected_target),
        "selected_model" => inspect(crucible_decision.selected_model),
        "trace_id" => trace_id
      },
      backend_label: :crucible_policy,
      runtime_profile: :crucible_forward_pass,
      margins: %{policy_confidence: decision && decision.confidence}
    }

    from_logits(logits, messages_or_hash,
      router_decision_ref: fetch(attrs, :router_decision_ref, decision_ref(decision)),
      coordination_run_ref:
        fetch(attrs, :coordination_run_ref, generated_ref("coordination-run")),
      router_artifact_ref: fetch(attrs, :router_artifact_ref, "crucible-policy:first-slice"),
      extractor_ref: fetch(attrs, :extractor_ref, "crucible-forward-pass"),
      head_ref: fetch(attrs, :head_ref, "crucible-policy"),
      selected_role_ref: fetch(attrs, :selected_role_ref, "role:#{selected_role_id}"),
      confidence_band: fetch(attrs, :confidence_band, confidence_band_from_confidence(decision)),
      role_name: fetch(attrs, :role_name, role_name),
      trace_ref: fetch(attrs, :trace_ref, trace_id),
      route_hash: fetch(attrs, :route_hash, hash_term({:crucible_route, crucible_decision})),
      artifact_identity: fetch(attrs, :artifact_identity, crucible_decision.selected_model),
      metadata:
        Map.merge(fetch(attrs, :metadata, %{}), %{
          crucible_decision_id: decision && decision.decision_id,
          crucible_evidence_refs: (decision && decision.evidence_refs) || [],
          crucible_uncertainty: decision && decision.uncertainty
        })
    )
  end

  @spec from_route(map(), [map()] | String.t() | nil, keyword() | map()) ::
          {:ok, RouteDecision.t()} | {:error, term()}
  def from_route(route, messages_or_hash \\ nil, attrs \\ []) when is_map(route) do
    agent_logits = list_or_nil(field(route, :agent_logits))
    role_logits = list_or_nil(field(route, :role_logits))
    selected_agent_id = field(route, :agent_id, field(route, :selected_agent_id, 0))
    selected_role_id = field(route, :role_id, field(route, :selected_role_id, 0))

    margins =
      field(route, :margins, %{agent: top_margin(agent_logits), role: top_margin(role_logits)})

    logits = %RouteLogits{
      role_logits: role_logits,
      agent_logits: agent_logits,
      selected_role_id: selected_role_id,
      selected_agent_id: selected_agent_id,
      token_count: field(route, :token_count, 0),
      transcript_hash: transcript_hash(messages_or_hash, field(route, :transcript_hash)),
      route_hash_inputs: field(route, :route_hash_inputs, %{}),
      backend_label: field(route, :backend_label, "coordinator-core"),
      runtime_profile: field(route, :runtime_profile, :core),
      margins: margins
    }

    from_logits(logits, messages_or_hash, attrs)
  end

  @spec to_trace_map(RouteDecision.t()) :: map()
  def to_trace_map(%RouteDecision{} = decision) do
    %{
      agent_id: decision.selected_agent_id,
      role_id: decision.selected_role_id,
      role_name: decision.role_name,
      margins: decision.margins,
      transcript_hash: decision.transcript_hash,
      route_hash: decision.route_hash,
      route_hash_inputs: decision.route_hash_inputs,
      selection_modes: %{agent: :argmax, role: :argmax},
      artifact_identity: decision.artifact_identity,
      metadata: decision.metadata
    }
  end

  defp attrs_map(attrs) when is_list(attrs), do: Map.new(attrs)
  defp attrs_map(attrs) when is_map(attrs), do: attrs

  defp transcript_hash(nil, nil), do: hash_term([])
  defp transcript_hash(nil, fallback) when is_binary(fallback), do: fallback
  defp transcript_hash(hash, _fallback) when is_binary(hash), do: hash
  defp transcript_hash(messages, _fallback) when is_list(messages), do: hash_term(messages)

  defp confidence_band(%{agent: agent, role: role}) when is_number(agent) and is_number(role) do
    cond do
      agent >= 1.0 and role >= 1.0 -> :high
      agent >= 0.1 and role >= 0.1 -> :medium
      true -> :low
    end
  end

  defp confidence_band(_), do: :unknown

  defp confidence_band_from_confidence(%{confidence: confidence}) when is_number(confidence) do
    cond do
      confidence >= 0.8 -> :high
      confidence >= 0.5 -> :medium
      true -> :low
    end
  end

  defp confidence_band_from_confidence(_decision), do: :unknown

  defp top_margin(nil), do: nil

  defp top_margin(values) when is_list(values) do
    case values |> Enum.sort(:desc) |> Enum.take(2) do
      [first, second] when is_number(first) and is_number(second) -> first - second
      _ -> nil
    end
  end

  defp list_or_nil(nil), do: nil
  defp list_or_nil(values) when is_list(values), do: values
  defp list_or_nil(other), do: other

  defp fetch(attrs, field, default \\ nil),
    do: Map.get(attrs, field, Map.get(attrs, Atom.to_string(field), default))

  defp field(map, field, default \\ nil),
    do: Map.get(map, field, Map.get(map, Atom.to_string(field), default))

  defp generated_ref(prefix), do: "#{prefix}:#{System.unique_integer([:positive])}"

  defp decision_ref(%{decision_id: decision_id}) when is_binary(decision_id), do: decision_id
  defp decision_ref(_decision), do: generated_ref("route-decision")

  defp hash_term(value) do
    binary =
      value
      |> normalize_for_hash()
      |> :erlang.term_to_binary([:compressed])

    :crypto.hash(:sha256, binary)
    |> Base.encode16(case: :lower)
  end

  defp normalize_for_hash(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> normalize_for_hash()
  end

  defp normalize_for_hash(value) when is_map(value) do
    value
    |> Enum.to_list()
    |> Enum.sort_by(fn {key, _value} -> normalize_key(key) end)
    |> Enum.map(fn {key, nested} -> {normalize_key(key), normalize_for_hash(nested)} end)
    |> Map.new()
  end

  defp normalize_for_hash(value) when is_list(value), do: Enum.map(value, &normalize_for_hash/1)

  defp normalize_for_hash(value) when is_tuple(value),
    do: value |> Tuple.to_list() |> normalize_for_hash()

  defp normalize_for_hash(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_for_hash(value) when is_number(value), do: value
  defp normalize_for_hash(value) when is_binary(value), do: value
  defp normalize_for_hash(value), do: inspect(value)

  defp normalize_key(nil), do: ""
  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key) when is_integer(key), do: Integer.to_string(key)
  defp normalize_key(key), do: inspect(key)
end
