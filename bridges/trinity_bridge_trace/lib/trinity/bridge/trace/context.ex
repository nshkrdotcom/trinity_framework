defmodule Trinity.Bridge.Trace.Context do
  @moduledoc """
  Trace context and option parsing for bridge-backed coordinator runs.
  """

  alias Trinity.Bridge.Trace.JsonlSink
  alias Trinity.Coordinator.TraceEvent

  defstruct [:run_id, :content, :sink, :enabled, :schema_version, redaction_values: []]

  @schema_version 1

  @type t :: %__MODULE__{
          run_id: String.t(),
          content: :hash | :full | atom(),
          sink: JsonlSink.t() | nil,
          enabled: boolean(),
          schema_version: pos_integer(),
          redaction_values: [String.t()]
        }

  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    enabled = Keyword.get(opts, :enabled, false)
    run_id = Keyword.get(opts, :run_id, default_run_id())
    content = Keyword.get(opts, :content, :hash)
    redaction_values = normalize_redaction_values(Keyword.get(opts, :redaction_values, []))

    %__MODULE__{
      run_id: run_id,
      content: content,
      enabled: enabled,
      sink: build_sink(enabled, opts, content, redaction_values),
      schema_version: @schema_version,
      redaction_values: redaction_values
    }
  end

  @spec write(t(), TraceEvent.t()) :: :ok | {:error, term()}
  def write(%__MODULE__{enabled: false}, _event), do: :ok
  def write(%__MODULE__{enabled: true, sink: nil}, _event), do: {:error, :trace_sink_missing}

  def write(%__MODULE__{enabled: true} = context, %TraceEvent{} = event) do
    event = enrich_event(context, event)
    JsonlSink.write_event(context.sink, event)
  end

  def write(%__MODULE__{}, _event), do: {:error, :invalid_trace_event}

  defp build_sink(false, _opts, _content, _redaction_values), do: nil

  defp build_sink(true, opts, content, redaction_values) do
    case Keyword.get(opts, :sink) do
      %JsonlSink{} = sink ->
        sink

      {:jsonl, path} ->
        JsonlSink.new!(
          path: path,
          content: content,
          redaction_values: redaction_values,
          schema_version: @schema_version
        )

      nil ->
        raise ArgumentError, "trace sink required when tracing is enabled"

      other ->
        raise ArgumentError, "unsupported trace sink: #{inspect(other)}"
    end
  end

  defp enrich_event(%__MODULE__{} = context, %TraceEvent{} = event) do
    %TraceEvent{
      event
      | coordination_run_ref: event.coordination_run_ref || context.run_id,
        timestamp_ms: event.timestamp_ms || System.system_time(:millisecond)
    }
  end

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

  defp default_run_id, do: "run_" <> Integer.to_string(System.unique_integer([:positive]))
end
