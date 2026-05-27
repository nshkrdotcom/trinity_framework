defmodule Trinity.Bridge.Trace.JsonlSink do
  @moduledoc """
  `Trinity.Coordinator.TraceSink` implementation that writes compatibility JSONL.
  """

  @behaviour Trinity.Coordinator.TraceSink

  alias AITrace.{Event, Span}
  alias CrucibleSignalTrace.ForwardTrace
  alias Trinity.Bridge.Trace.{JSONL, Redactor}
  alias Trinity.Coordinator.TraceEvent

  @schema_version 1

  @enforce_keys [:path]
  defstruct path: nil,
            content: :hash,
            include_ai_trace: false,
            include_refs: false,
            redaction_values: [],
            schema_version: @schema_version

  @type t :: %__MODULE__{
          path: String.t(),
          content: :hash | :full | atom(),
          include_ai_trace: boolean(),
          include_refs: boolean(),
          redaction_values: [String.t()],
          schema_version: pos_integer()
        }

  def emit(event, opts \\ [])

  @impl true
  def emit(%TraceEvent{} = event, opts) when is_list(opts) do
    with {:ok, sink} <- sink_from_opts(opts) do
      write_event(sink, event)
    end
  end

  def emit(_event, _opts), do: {:error, :invalid_trace_event}

  @doc "Writes a Crucible forward trace as Trinity-compatible JSONL records."
  @spec emit_crucible_trace(ForwardTrace.t(), keyword()) :: :ok | {:error, term()}
  def emit_crucible_trace(trace, opts \\ [])

  def emit_crucible_trace(%ForwardTrace{} = trace, opts) when is_list(opts) do
    with {:ok, sink} <- sink_from_opts(opts) do
      write_crucible_trace(sink, trace, opts)
    end
  end

  def emit_crucible_trace(_trace, _opts), do: {:error, :invalid_crucible_trace}

  @doc "Builds a JSONL sink from options."
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts), do: opts |> Map.new() |> new()

  def new(opts) when is_map(opts) do
    case fetch(opts, :path) || fetch(opts, :jsonl_path) do
      path when is_binary(path) and path != "" ->
        {:ok,
         %__MODULE__{
           path: path,
           content: fetch(opts, :content, :hash),
           include_ai_trace: fetch(opts, :include_ai_trace, false),
           include_refs: fetch(opts, :include_refs, false),
           redaction_values: normalize_redaction_values(fetch(opts, :redaction_values, [])),
           schema_version: fetch(opts, :schema_version, @schema_version)
         }}

      _other ->
        {:error, :trace_jsonl_path_required}
    end
  end

  def new(_opts), do: {:error, :invalid_trace_sink_opts}

  @doc "Builds a JSONL sink from options or raises on invalid configuration."
  @spec new!(keyword() | map()) :: t()
  def new!(opts) do
    case new(opts) do
      {:ok, sink} -> sink
      {:error, reason} -> raise ArgumentError, "invalid trace JSONL sink: #{inspect(reason)}"
    end
  end

  @doc "Writes one coordinator trace event to a sink."
  @spec write_event(t(), TraceEvent.t()) :: :ok | {:error, term()}
  def write_event(%__MODULE__{} = sink, %TraceEvent{} = event) do
    JSONL.append(sink.path, record(sink, event))
  end

  @doc "Writes one Crucible forward trace and its signal records to a sink."
  @spec write_crucible_trace(t(), ForwardTrace.t(), keyword()) :: :ok | {:error, term()}
  def write_crucible_trace(%__MODULE__{} = sink, %ForwardTrace{} = trace, opts \\ []) do
    trace
    |> crucible_records(sink, opts)
    |> Enum.reduce_while(:ok, fn record, :ok ->
      case JSONL.append(sink.path, record) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp sink_from_opts(opts) do
    case Keyword.get(opts, :sink) do
      %__MODULE__{} = sink -> {:ok, sink}
      nil -> new(opts)
      other -> {:error, {:unsupported_trace_sink, other}}
    end
  end

  defp record(%__MODULE__{} = sink, %TraceEvent{} = event) do
    attributes = attributes(sink, event)
    ai_event = Event.new(event_name(event.event_type), attributes)

    span =
      event.event_type |> span_name() |> Span.new() |> Span.add_event(ai_event) |> Span.finish()

    %{
      schema_version: sink.schema_version,
      event: event.event_type,
      run_id: run_id(event),
      timestamp_ms: event.timestamp_ms || System.system_time(:millisecond)
    }
    |> Map.merge(attributes.payload)
    |> maybe_put_metadata(attributes.metadata)
    |> maybe_put_refs(sink, event)
    |> maybe_put_ai_trace(sink, span, ai_event)
  end

  defp crucible_records(%ForwardTrace{} = trace, %__MODULE__{} = sink, opts) do
    timestamp_ms = Keyword.get(opts, :timestamp_ms, System.system_time(:millisecond))
    run_id = Keyword.get(opts, :coordination_run_ref) || trace.trace_id

    [
      %{
        schema_version: sink.schema_version,
        event: :crucible_forward_trace,
        run_id: run_id,
        timestamp_ms: timestamp_ms,
        trace_id: trace.trace_id,
        model_ref: trace.model_ref,
        input_hash: trace.input_hash,
        tap_plan_ref: trace.tap_plan_ref,
        signal_count: length(trace.signal_records),
        final_logits_ref: trace.final_logits && trace.final_logits.signal_id,
        metadata: redact_payload(sink, trace.metadata)
      }
    ] ++
      Enum.map(trace.signal_records, fn record ->
        %{
          schema_version: sink.schema_version,
          event: :crucible_signal_record,
          run_id: run_id,
          timestamp_ms: timestamp_ms,
          trace_id: trace.trace_id,
          signal_id: record.signal_ref.signal_id,
          signal_type: record.signal_ref.signal_type,
          layer_index: record.signal_ref.layer_index,
          token_index: record.signal_ref.token_index,
          capture_mode: record.capture_mode,
          summary: redact_payload(sink, normalize_structs(record.summary)),
          value_ref: record.value_ref,
          metadata: redact_payload(sink, record.metadata)
        }
      end)
  end

  defp attributes(%__MODULE__{} = sink, %TraceEvent{} = event) do
    %{
      payload: redact_payload(sink, event.payload),
      metadata: redact_payload(sink, event.metadata)
    }
  end

  defp redact_payload(%__MODULE__{content: :full, redaction_values: values}, payload) do
    payload = normalize_structs(payload)
    Redactor.redact_values(payload, values)
  end

  defp redact_payload(%__MODULE__{redaction_values: values}, payload) do
    payload = normalize_structs(payload)

    payload
    |> Redactor.redact(:redacted)
    |> Redactor.redact_values(values)
  end

  defp normalize_structs(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> normalize_structs()
  end

  defp normalize_structs(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {key, normalize_structs(nested)} end)
  end

  defp normalize_structs(value) when is_list(value), do: Enum.map(value, &normalize_structs/1)
  defp normalize_structs(value), do: value

  defp event_name(event_type), do: "trinity." <> normalize_event_type(event_type)
  defp span_name(event_type), do: "trinity.trace." <> normalize_event_type(event_type)

  defp run_id(%TraceEvent{coordination_run_ref: run_id}) when is_binary(run_id), do: run_id
  defp run_id(%TraceEvent{trace_ref: trace_ref}) when is_binary(trace_ref), do: trace_ref
  defp run_id(_event), do: nil

  defp maybe_put_metadata(record, metadata) when metadata in [%{}, nil], do: record
  defp maybe_put_metadata(record, metadata), do: Map.put(record, :metadata, metadata)

  defp maybe_put_refs(record, %__MODULE__{include_refs: true}, %TraceEvent{} = event) do
    record
    |> maybe_put(:event_ref, event.event_ref)
    |> maybe_put(:trace_ref, event.trace_ref)
  end

  defp maybe_put_refs(record, _sink, _event), do: record

  defp maybe_put_ai_trace(record, %__MODULE__{include_ai_trace: true}, span, ai_event) do
    Map.put(record, :aitrace, %{
      event_name: ai_event.name,
      span_name: span.name,
      status: span.status
    })
  end

  defp maybe_put_ai_trace(record, _sink, _span, _ai_event), do: record

  defp maybe_put(record, _key, nil), do: record
  defp maybe_put(record, key, value), do: Map.put(record, key, value)

  defp normalize_event_type(event_type) when is_atom(event_type), do: Atom.to_string(event_type)
  defp normalize_event_type(event_type) when is_binary(event_type), do: event_type
  defp normalize_event_type(event_type), do: inspect(event_type)

  defp normalize_redaction_values(values) when is_list(values) do
    values
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_redaction_values(value) when is_binary(value),
    do: normalize_redaction_values([value])

  defp normalize_redaction_values(_value), do: []

  defp fetch(attrs, field, default \\ nil),
    do: Map.get(attrs, field, Map.get(attrs, Atom.to_string(field), default))
end
