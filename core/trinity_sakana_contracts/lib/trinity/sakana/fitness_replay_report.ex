defmodule Trinity.Sakana.FitnessReplayReport do
  @moduledoc "Schema-versioned score replay report for Sakana fitness examples."

  @schema_version "trinity.sakana.fitness_replay_report.v1"
  @fields [
    :fitness_path,
    :manifest_path,
    :record_count,
    :score_mismatch_count,
    :label_mismatch_count,
    :mismatches,
    :component_summary,
    :group_summary,
    :reflex_economics,
    :dataset_digest,
    :status,
    :status_reason
  ]

  @enforce_keys [:schema_version | @fields]
  defstruct @enforce_keys

  @spec schema_version() :: String.t()
  def schema_version, do: @schema_version

  @spec new(keyword() | map()) :: {:ok, struct()} | {:error, term()}
  def new(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = Map.new(attrs)

    with :ok <- validate_fields(attrs),
         :ok <-
           validate_non_negative(attrs, [
             :record_count,
             :score_mismatch_count,
             :label_mismatch_count
           ]) do
      {:ok,
       struct!(__MODULE__, Map.put(Map.take(attrs, @fields), :schema_version, @schema_version))}
    end
  end

  def new(_attrs), do: {:error, :invalid_fitness_replay_report}

  @spec new!(keyword() | map()) :: struct()
  def new!(attrs) do
    case new(attrs) do
      {:ok, report} -> report
      {:error, reason} -> raise ArgumentError, "invalid fitness replay report: #{inspect(reason)}"
    end
  end

  @spec to_map(struct()) :: map()
  def to_map(%__MODULE__{} = report), do: Map.from_struct(report)

  defp validate_fields(attrs) do
    missing = Enum.reject(@fields, &Map.has_key?(attrs, &1))
    if missing == [], do: :ok, else: {:error, {:missing_fields, missing}}
  end

  defp validate_non_negative(attrs, fields) do
    if Enum.all?(fields, &(is_integer(Map.get(attrs, &1)) and Map.get(attrs, &1) >= 0)),
      do: :ok,
      else: {:error, :invalid_counts}
  end
end
