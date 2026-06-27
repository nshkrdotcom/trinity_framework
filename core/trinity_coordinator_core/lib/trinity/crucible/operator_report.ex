defmodule Trinity.Crucible.OperatorReport do
  @moduledoc """
  Stable envelope for Trinity Crucible operator reports.
  """

  @derive Jason.Encoder
  defstruct schema: nil,
            mode: nil,
            ok: true,
            trace_id: nil,
            generated_at: nil,
            validation: %{},
            summaries: %{},
            payload: %{},
            artifact_paths: %{},
            metadata: %{}

  @type t :: %__MODULE__{}

  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = attrs_map(attrs)

    with schema when is_binary(schema) and schema != "" <- field(attrs, :schema) do
      {:ok,
       %__MODULE__{
         schema: schema,
         mode: field(attrs, :mode),
         ok: field(attrs, :ok, true),
         trace_id: field(attrs, :trace_id),
         generated_at: field(attrs, :generated_at, DateTime.utc_now()),
         validation: field(attrs, :validation, %{}),
         summaries: field(attrs, :summaries, %{}),
         payload: field(attrs, :payload, %{}),
         artifact_paths: field(attrs, :artifact_paths, %{}),
         metadata: field(attrs, :metadata, %{})
       }}
    else
      _value -> {:error, :missing_schema}
    end
  end

  @spec new!(keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, report} -> report
      {:error, reason} -> raise ArgumentError, "invalid operator report: #{inspect(reason)}"
    end
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = report) do
    report
    |> Map.from_struct()
    |> Map.update!(:generated_at, &format_time/1)
    |> merge_payload()
  end

  defp merge_payload(%{payload: payload} = report) when is_map(payload) do
    report
    |> Map.delete(:payload)
    |> Map.merge(payload)
  end

  defp format_time(%DateTime{} = time), do: DateTime.to_iso8601(time)
  defp format_time(time), do: time

  defp attrs_map(attrs) when is_list(attrs), do: Map.new(attrs)
  defp attrs_map(attrs) when is_map(attrs), do: attrs

  defp field(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end
