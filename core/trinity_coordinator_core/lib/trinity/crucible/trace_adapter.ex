defmodule Trinity.Crucible.TraceAdapter do
  @moduledoc """
  Converts Trinity route-runtime evidence into bounded Crucible trace records.
  """

  alias Crucible.{ForwardTrace, SignalRecord, TensorSummary}
  alias CruciblePolicy.RouteDecision, as: CrucibleRouteDecision
  alias CrucibleSignalTrace.{JSONL, LayerTrajectory}
  alias CrucibleTap.TapPlan

  alias Trinity.Coordinator.{RoleInjector, RouteLogits, TraceEvent}
  alias Trinity.Crucible.RequestContext

  @exla_backend_prefix "EXLA" <> ".Backend<"

  @spec from_logits(RouteLogits.t(), [map()] | RequestContext.t(), TapPlan.t() | nil, keyword()) ::
          ForwardTrace.t()
  def from_logits(%RouteLogits{} = logits, messages_or_context, tap_plan, opts \\ []) do
    context = request_context(messages_or_context, opts)

    trace_id =
      Keyword.get(opts, :trace_id) || context.trace_ref || "trace:crucible:#{hash(logits)}"

    model_id = Keyword.get(opts, :model_id) || model_id(logits, context)
    run_id = Keyword.get(opts, :run_id) || context.coordination_run_ref
    values = logits_values(logits)
    metadata = trace_metadata(context, logits, model_id)
    final_record = final_logits_record(trace_id, run_id, model_id, values, logits, metadata)
    trajectory = trajectory_from_plan(tap_plan, logits)

    ForwardTrace.new!(
      trace_id: trace_id,
      run_id: run_id,
      provider_kind: :trinity_route_logits,
      model_id: model_id,
      model_family: :route_logits,
      backend: trace_backend(logits),
      input_hash: logits.transcript_hash || hash(context.messages),
      tap_plan_ref: tap_plan && tap_plan.plan_id,
      signals: [final_record],
      layer_trajectory: trajectory,
      final_logits: final_record,
      policy_decision_refs: [],
      metadata: metadata
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
      selected_model: trace.model_id,
      confidence: confidence,
      uncertainty: %CruciblePolicy.Uncertainty{
        margin: margin(logits),
        policy_confidence: confidence,
        metadata: %{source: :route_logits_adapter}
      },
      evidence_refs: Enum.map(trace.signals, & &1.signal_id),
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
      model_id: trace.model_id,
      input_hash: trace.input_hash,
      tap_plan_ref: trace.tap_plan_ref,
      signals: Enum.map(trace.signals, &signal_record_map/1),
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
      Enum.map(trace.signals, fn record ->
        JSONL.v4_event(:signal_record,
          trace_id: trace.trace_id,
          token_index: record.token_index || token_index,
          layer: record.layer_index,
          signal: record
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

  @spec summarize_trace(ForwardTrace.t()) :: map()
  def summarize_trace(%ForwardTrace{} = trace) do
    %{
      trace_id: trace.trace_id,
      run_id: trace.run_id,
      provider_kind: trace.provider_kind,
      model_id: trace.model_id,
      model_family: trace.model_family,
      backend: trace.backend,
      tap_plan_ref: trace.tap_plan_ref,
      signal_count: length(trace.signals),
      final_logits_ref: trace.final_logits && trace.final_logits.signal_id,
      has_capability_report?: not is_nil(trace.capability_report),
      has_layer_trajectory?: not is_nil(trace.layer_trajectory)
    }
  end

  @spec summarize_signals(ForwardTrace.t()) :: map()
  def summarize_signals(%ForwardTrace{} = trace) do
    %{
      count: length(trace.signals),
      by_type: Enum.frequencies_by(trace.signals, & &1.signal_type),
      by_status: Enum.frequencies_by(trace.signals, & &1.capability_status)
    }
  end

  @spec summarize_capabilities(ForwardTrace.t()) :: map()
  def summarize_capabilities(%ForwardTrace{} = trace) do
    report = trace.capability_report

    %{
      signal_count: length(trace.signals),
      capability_report?: not is_nil(report),
      supported: capability_list(report, :supported),
      unsupported: capability_list(report, :unsupported),
      required_missing: capability_list(report, :required_missing),
      inferred_signal_types: trace.signals |> Enum.map(& &1.signal_type) |> Enum.uniq()
    }
  end

  @spec extract_route_evidence(ForwardTrace.t()) :: [map()]
  def extract_route_evidence(%ForwardTrace{} = trace) do
    trace.signals
    |> Enum.filter(&(&1.signal_type in [:final_logits, :intermediate_logits, :decode_margin]))
    |> Enum.map(&evidence_record/1)
  end

  @spec extract_generation_evidence(ForwardTrace.t()) :: [map()]
  def extract_generation_evidence(%ForwardTrace{} = trace) do
    trace.signals
    |> Enum.filter(&(&1.signal_type in [:generation_token, :generation_step_logits]))
    |> Enum.map(&evidence_record/1)
  end

  @spec extract_trajectory_evidence(ForwardTrace.t()) :: [map()]
  def extract_trajectory_evidence(%ForwardTrace{layer_trajectory: %LayerTrajectory{} = trajectory}) do
    Enum.map(trajectory.points, fn point ->
      %{
        layer_index: Map.get(point, :layer_index),
        signal_ref: Map.get(point, :signal_ref),
        metadata: Map.get(point, :metadata, %{})
      }
    end)
  end

  def extract_trajectory_evidence(%ForwardTrace{}), do: []

  @spec render_operator_table(ForwardTrace.t() | map()) :: String.t()
  def render_operator_table(%ForwardTrace{} = trace), do: trace |> summarize_trace() |> render_operator_table()

  def render_operator_table(summary) when is_map(summary) do
    rows = [
      {"trace", Map.get(summary, :trace_id)},
      {"model", Map.get(summary, :model_id)},
      {"provider", Map.get(summary, :provider_kind)},
      {"signals", Map.get(summary, :signal_count)}
    ]

    rows
    |> Enum.map(fn {label, value} -> "#{label}: #{value}" end)
    |> Enum.join("\n")
  end

  @spec write_artifact_index(Trinity.Crucible.ArtifactPaths.t(), [map()]) :: String.t()
  def write_artifact_index(%Trinity.Crucible.ArtifactPaths{} = paths, entries),
    do: Trinity.Crucible.ArtifactPaths.write_artifact_index!(paths, entries)

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

  defp final_logits_record(
         trace_id,
         run_id,
         model_id,
         values,
         %RouteLogits{} = logits,
         metadata
       ) do
    summary = TensorSummary.compute(values, entropy: true, top_k: 4)

    SignalRecord.new!(
      trace_id: trace_id,
      run_id: run_id,
      signal_id: "trinity:final_logits:#{hash({trace_id, model_id})}",
      signal_type: :final_logits,
      provider_kind: :trinity_route_logits,
      model_id: model_id,
      model_family: :route_logits,
      backend: trace_backend(logits),
      dtype: summary.dtype,
      shape: summary.shape,
      rank: summary.rank,
      token_index: 0,
      node_name: "trinity.route_logits",
      capture_method: :route_logits_projection,
      capability_status: :captured,
      tensor_summary: summary,
      metadata: signal_metadata(metadata)
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
      signal_id: record.signal_id,
      signal_type: record.signal_type,
      capture_method: record.capture_method,
      tensor_summary: record.tensor_summary,
      tensor_ref: record.tensor_ref,
      metadata: record.metadata
    }
  end

  defp trajectory_map(nil), do: nil
  defp trajectory_map(%LayerTrajectory{} = trajectory), do: trajectory.points

  defp capability_list(nil, _field), do: []

  defp capability_list(report, field) when is_map(report) do
    Map.get(report, field, Map.get(report, Atom.to_string(field), [])) || []
  end

  defp evidence_record(%SignalRecord{} = record) do
    %{
      signal_id: record.signal_id,
      signal_type: record.signal_type,
      capability_status: record.capability_status,
      tensor_summary: record.tensor_summary,
      metadata: record.metadata
    }
  end

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

  defp model_id(%RouteLogits{} = logits, %RequestContext{} = context) do
    profile = runtime_profile_map(context)

    cond do
      is_binary(field(profile, :model_id)) -> field(profile, :model_id)
      is_atom(context.runtime_profile) -> Atom.to_string(context.runtime_profile)
      is_binary(context.runtime_profile) -> context.runtime_profile
      is_atom(logits.runtime_profile) -> Atom.to_string(logits.runtime_profile)
      is_binary(logits.runtime_profile) -> logits.runtime_profile
      true -> "trinity-route-runtime"
    end
  end

  defp trace_metadata(%RequestContext{} = context, %RouteLogits{} = logits, model_id) do
    profile = runtime_profile_map(context)

    %{
      task_type: context.task_type,
      model_id: model_id,
      backend_label: backend_label(logits),
      runtime_profile: runtime_profile_name(context, logits),
      runtime_kind: :route_logits_adapter,
      adapter_id: field(profile, :adapter_id),
      artifact_ref: field(profile, :artifact_ref),
      artifact_repo: field(profile, :artifact_repo),
      artifact_revision: field(profile, :artifact_revision),
      artifact_manifest_sha256: field(profile, :artifact_manifest_sha256),
      artifact_manifest_sha256_actual: field(profile, :artifact_manifest_sha256_actual),
      artifact_pin_manifest_sha256: field(profile, :artifact_pin_manifest_sha256),
      artifact_pin_verified?: field(profile, :artifact_pin_verified?),
      local_artifact_root: field(profile, :artifact_root),
      local_artifact_manifest_path: field(profile, :artifact_manifest_path),
      local_artifact_pin_path: field(profile, :artifact_pin_path),
      artifact_status: field(profile, :artifact_status),
      artifact_status_reason: field(profile, :artifact_status_reason),
      manifest_status: field(profile, :manifest_status),
      artifact_layout: field(profile, :artifact_layout),
      router_head_artifact: field(profile, :router_head_artifact),
      artifact_available?: field(profile, :artifact_available?),
      qwen_base_model?: field(profile, :qwen_base_model?),
      sakana_route_artifact?: field(profile, :sakana_route_artifact?),
      runtime_loaded?: field(profile, :runtime_loaded?),
      executed_runtime?: field(profile, :executed_runtime?),
      qwen_loaded?: field(profile, :qwen_loaded?),
      router_head_shape: field(profile, :router_head_shape),
      selected_tensor_count: field(profile, :selected_tensor_count),
      scale_offset_count: field(profile, :scale_offset_count),
      source_vector_shape: field(profile, :source_vector_shape),
      transcript_hash: logits.transcript_hash || hash(context.messages),
      selected_agent_id: logits.selected_agent_id,
      selected_role_id: logits.selected_role_id,
      logit_margin: margin(logits),
      token_count: logits.token_count,
      route_hash_inputs: logits.route_hash_inputs
    }
  end

  defp signal_metadata(metadata) do
    metadata
    |> Map.take([
      :model_id,
      :backend_label,
      :runtime_profile,
      :adapter_id,
      :artifact_ref,
      :artifact_repo,
      :artifact_revision,
      :artifact_manifest_sha256,
      :artifact_manifest_sha256_actual,
      :artifact_pin_manifest_sha256,
      :artifact_pin_verified?,
      :local_artifact_root,
      :local_artifact_manifest_path,
      :local_artifact_pin_path,
      :artifact_status,
      :artifact_status_reason,
      :manifest_status,
      :artifact_layout,
      :router_head_artifact,
      :artifact_available?,
      :qwen_base_model?,
      :sakana_route_artifact?,
      :runtime_loaded?,
      :executed_runtime?,
      :qwen_loaded?,
      :router_head_shape,
      :selected_tensor_count,
      :scale_offset_count,
      :source_vector_shape
    ])
    |> Map.put(:source, :trinity_route_logits)
  end

  defp runtime_profile_map(%RequestContext{runtime_profile: profile}) when is_map(profile),
    do: profile

  defp runtime_profile_map(_context), do: %{}

  defp runtime_profile_name(%RequestContext{} = context, %RouteLogits{} = logits) do
    profile = runtime_profile_map(context)

    cond do
      is_atom(field(profile, :name)) -> Atom.to_string(field(profile, :name))
      is_binary(field(profile, :name)) -> field(profile, :name)
      is_atom(logits.runtime_profile) -> Atom.to_string(logits.runtime_profile)
      is_binary(logits.runtime_profile) -> logits.runtime_profile
      is_atom(context.runtime_profile) -> Atom.to_string(context.runtime_profile)
      is_binary(context.runtime_profile) -> context.runtime_profile
      true -> nil
    end
  end

  defp backend_label(%RouteLogits{} = logits) do
    cond do
      is_atom(logits.backend_label) -> Atom.to_string(logits.backend_label)
      is_binary(logits.backend_label) -> logits.backend_label
      is_atom(logits.runtime_profile) -> Atom.to_string(logits.runtime_profile)
      is_binary(logits.runtime_profile) -> logits.runtime_profile
      true -> nil
    end
  end

  defp trace_backend(%RouteLogits{} = logits) do
    logits
    |> backend_label()
    |> bounded_backend()
  end

  defp bounded_backend("mock_tiny"), do: :mock_tiny
  defp bounded_backend("binary"), do: :binary
  defp bounded_backend("host_exla"), do: :exla_host
  defp bounded_backend("cuda_exla"), do: :exla_cuda

  defp bounded_backend(label) when is_binary(label) do
    cond do
      String.contains?(label, @exla_backend_prefix <> "cuda") -> :exla_cuda
      String.contains?(label, @exla_backend_prefix <> "host") -> :exla_host
      String.contains?(label, "cuda") -> :exla_cuda
      String.contains?(label, "host") -> :exla_host
      true -> :route_logits
    end
  end

  defp bounded_backend(_label), do: :route_logits

  defp field(map, field), do: field(map, field, nil)

  defp field(map, field, default) when is_map(map),
    do: Map.get(map, field, Map.get(map, Atom.to_string(field), default))

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
