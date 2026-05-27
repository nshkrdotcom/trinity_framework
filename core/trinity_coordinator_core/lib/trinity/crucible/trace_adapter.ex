defmodule Trinity.Crucible.TraceAdapter do
  @moduledoc """
  Converts Trinity route-runtime evidence into bounded Crucible trace records.
  """

  alias CruciblePolicy.RouteDecision, as: CrucibleRouteDecision
  alias CrucibleSignal.{SignalRef, TensorSummary}
  alias CrucibleSignalTrace.Export.AITrace.V1, as: AITraceExport
  alias CrucibleSignalTrace.{ForwardTrace, JSONL, LayerTrajectory, SignalRecord}
  alias CrucibleTap.TapPlan

  alias Trinity.Coordinator.{RoleInjector, RouteLogits, TraceEvent}
  alias Trinity.Crucible.RequestContext

  @spec from_logits(RouteLogits.t(), [map()] | RequestContext.t(), TapPlan.t() | nil, keyword()) ::
          ForwardTrace.t()
  def from_logits(%RouteLogits{} = logits, messages_or_context, tap_plan, opts \\ []) do
    context = request_context(messages_or_context, opts)

    trace_id =
      Keyword.get(opts, :trace_id) || context.trace_ref || "trace:crucible:#{hash(logits)}"

    model_ref = Keyword.get(opts, :model_ref) || model_ref(logits, context)
    values = logits_values(logits)
    final_ref = final_logits_ref(trace_id, model_ref, length(values))
    final_record = final_logits_record(final_ref, values)
    trajectory = trajectory_from_plan(tap_plan, logits)

    ForwardTrace.new!(
      trace_id: trace_id,
      model_ref: model_ref,
      input_hash: logits.transcript_hash || hash(context.messages),
      tap_plan_ref: tap_plan && tap_plan.plan_id,
      signal_records: [final_record],
      layer_trajectory: trajectory,
      final_logits: final_ref,
      policy_decision_refs: [],
      metadata: %{
        task_type: context.task_type,
        runtime_profile: logits.runtime_profile,
        runtime_kind: :legacy_route_logits_adapter,
        logit_margin: margin(logits),
        token_count: logits.token_count,
        route_hash_inputs: logits.route_hash_inputs
      }
    )
  end

  @spec route_decision_from_logits(RouteLogits.t(), ForwardTrace.t(), keyword()) ::
          CrucibleRouteDecision.t()
  def route_decision_from_logits(%RouteLogits{} = logits, %ForwardTrace{} = trace, opts \\ []) do
    target = RoleInjector.role_atom(logits.selected_role_id)
    confidence = Keyword.get(opts, :confidence, confidence_from_logits(logits))
    decision_id = Keyword.get(opts, :decision_id, decision_id(trace.trace_id, target, logits))

    CrucibleRouteDecision.new!(
      decision_id: decision_id,
      trace_id: trace.trace_id,
      policy_ref: Keyword.get(opts, :policy_ref, "trinity:crucible:route-logits-policy"),
      selected_target: target,
      selected_model: trace.model_ref,
      confidence: confidence,
      uncertainty: %CruciblePolicy.Uncertainty{
        margin: margin(logits),
        policy_confidence: confidence,
        metadata: %{source: :route_logits_adapter}
      },
      evidence_refs: Enum.map(trace.signal_records, & &1.signal_ref.signal_id),
      metadata: %{
        adapter: :trinity_route_logits,
        selected_agent_id: logits.selected_agent_id,
        selected_role_id: logits.selected_role_id,
        runtime_profile: logits.runtime_profile
      }
    )
  end

  @spec to_trace_event(ForwardTrace.t(), keyword()) :: TraceEvent.t()
  def to_trace_event(%ForwardTrace{} = trace, opts \\ []) do
    %TraceEvent{
      event_ref: Keyword.get(opts, :event_ref, "trace-event:crucible:#{hash(trace.trace_id)}"),
      event_type: :crucible_forward_trace,
      trace_ref: trace.trace_id,
      coordination_run_ref: Keyword.get(opts, :coordination_run_ref),
      timestamp_ms: Keyword.get(opts, :timestamp_ms),
      payload: to_map(trace),
      metadata: %{schema: "trinity.crucible.forward_trace.v1"}
    }
  end

  @spec to_map(ForwardTrace.t()) :: map()
  def to_map(%ForwardTrace{} = trace) do
    %{
      schema: "trinity.crucible.forward_trace.v1",
      trace_id: trace.trace_id,
      model_ref: trace.model_ref,
      input_hash: trace.input_hash,
      tap_plan_ref: trace.tap_plan_ref,
      signals: Enum.map(trace.signal_records, &signal_record_map/1),
      trajectory: trajectory_map(trace.layer_trajectory),
      final_logits_ref: trace.final_logits && trace.final_logits.signal_id,
      policy_decision_refs: trace.policy_decision_refs,
      metadata: trace.metadata
    }
  end

  @spec to_jsonl_events(ForwardTrace.t(), keyword()) :: [map()]
  def to_jsonl_events(%ForwardTrace{} = trace, opts \\ []) do
    token_index = Keyword.get(opts, :token_index, 0)

    [JSONL.trace_start(trace.trace_id)] ++
      Enum.map(trace.signal_records, fn record ->
        JSONL.signal_record(
          trace.trace_id,
          record.signal_ref.token_index || token_index,
          record.signal_ref.layer_index,
          record
        )
      end) ++
      [
        JSONL.token_step(
          trace.trace_id,
          token_index,
          trace.final_logits && trace.final_logits.signal_id
        ),
        JSONL.trace_end(trace.trace_id, %{digest: ForwardTrace.digest(trace)})
      ]
  end

  @spec to_aitrace_evidence(ForwardTrace.t()) :: {:ok, map()} | {:error, term()}
  def to_aitrace_evidence(%ForwardTrace{} = trace) do
    AITraceExport.to_evidence(trace)
  end

  defp request_context(%RequestContext{} = context, _opts), do: context

  defp request_context(messages, opts) when is_list(messages) do
    RequestContext.from_messages(messages,
      task_type: Keyword.get(opts, :task_type),
      turn: Keyword.get(opts, :turn, 0),
      trace_ref: Keyword.get(opts, :trace_ref),
      coordination_run_ref: Keyword.get(opts, :coordination_run_ref),
      runtime_profile: Keyword.get(opts, :runtime_profile),
      metadata: Keyword.get(opts, :metadata, %{})
    )
  end

  defp final_logits_ref(trace_id, model_ref, count) do
    SignalRef.for_final_logits(
      trace_id: trace_id,
      signal_id: "trinity:final_logits:#{hash({trace_id, model_ref})}",
      model_ref: model_ref,
      shape: [count],
      capture_mode: :summary
    )
  end

  defp final_logits_record(%SignalRef{} = ref, values) do
    SignalRecord.new!(
      signal_ref: ref,
      summary: TensorSummary.from_list(values, entropy: true, top_k: 4),
      capture_mode: :summary,
      metadata: %{source: :trinity_route_logits}
    )
  end

  defp trajectory_from_plan(nil, _logits), do: nil

  defp trajectory_from_plan(%TapPlan{} = tap_plan, %RouteLogits{} = logits) do
    points =
      tap_plan.specs
      |> Enum.filter(&(&1.signal_spec.signal_type in [:middle_residuals, :layer_trajectory]))
      |> Enum.flat_map(fn spec -> List.wrap(spec.signal_spec.layers) end)
      |> Enum.reject(&(&1 in [:all, :final]))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(fn layer ->
        %{
          layer_index: layer,
          signal_ref: "trinity:trajectory:layer:#{layer}",
          vector: trajectory_vector(logits, layer),
          norm: nil,
          metadata: %{source: :route_logits_projection}
        }
      end)

    if points == [], do: nil, else: LayerTrajectory.new!(points)
  end

  defp trajectory_vector(%RouteLogits{} = logits, layer) do
    values = logits_values(logits)
    seed = max(layer, 1) / 100.0

    values
    |> Enum.take(4)
    |> case do
      [] -> [seed, seed + 0.1, seed + 0.2, seed + 0.3]
      taken -> Enum.map(taken, &(&1 * 1.0 + seed))
    end
  end

  defp signal_record_map(%SignalRecord{} = record) do
    %{
      signal_id: record.signal_ref.signal_id,
      signal_type: record.signal_ref.signal_type,
      capture_mode: record.capture_mode,
      summary: record.summary,
      value_ref: record.value_ref,
      metadata: record.metadata
    }
  end

  defp trajectory_map(nil), do: nil
  defp trajectory_map(%LayerTrajectory{} = trajectory), do: trajectory.points

  defp logits_values(%RouteLogits{} = logits) do
    [logits.agent_logits, logits.role_logits]
    |> Enum.flat_map(&numeric_list/1)
    |> case do
      [] -> [0.0]
      values -> values
    end
  end

  defp numeric_list(values) when is_list(values) do
    values
    |> List.flatten()
    |> Enum.filter(&is_number/1)
    |> Enum.map(&(&1 * 1.0))
  end

  defp numeric_list(_values), do: []

  defp model_ref(%RouteLogits{} = logits, %RequestContext{} = context) do
    cond do
      is_binary(logits.backend_label) -> logits.backend_label
      is_atom(logits.backend_label) -> Atom.to_string(logits.backend_label)
      is_atom(context.runtime_profile) -> Atom.to_string(context.runtime_profile)
      is_binary(context.runtime_profile) -> context.runtime_profile
      true -> "trinity-route-runtime"
    end
  end

  defp margin(%RouteLogits{margins: margins}) when is_map(margins) do
    margins
    |> Map.values()
    |> Enum.filter(&is_number/1)
    |> case do
      [] -> nil
      values -> Enum.min(values)
    end
  end

  defp margin(_logits), do: nil

  defp confidence_from_logits(%RouteLogits{} = logits) do
    case margin(logits) do
      value when is_number(value) -> max(0.0, min(0.99, 0.55 + value / 10.0))
      _ -> 0.64
    end
  end

  defp decision_id(trace_id, target, %RouteLogits{} = logits) do
    "trinity:crucible:route-decision:#{hash({trace_id, target, logits.selected_agent_id})}"
  end

  defp hash(value) do
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
