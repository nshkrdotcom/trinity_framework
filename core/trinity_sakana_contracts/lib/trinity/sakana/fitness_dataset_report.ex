defmodule Trinity.Sakana.FitnessDatasetReport do
  @moduledoc "Schema-versioned health report for exported Sakana fitness datasets."

  @schema_version "trinity.sakana.fitness_dataset_report.v1"
  @fields [
    :fitness_path,
    :manifest_path,
    :record_count,
    :positive_count,
    :neutral_count,
    :negative_count,
    :source_counts,
    :runtime_profiles,
    :artifact_refs,
    :route_path_counts,
    :reflex_counts,
    :missing_outcome_counts,
    :secret_scan,
    :digest,
    :manifest_digest_verified,
    :dataset_status,
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
         :ok <- validate_counts(attrs),
         :ok <- validate_status(attrs) do
      {:ok,
       struct!(__MODULE__, Map.put(Map.take(attrs, @fields), :schema_version, @schema_version))}
    end
  end

  def new(_attrs), do: {:error, :invalid_fitness_dataset_report}

  @spec new!(keyword() | map()) :: struct()
  def new!(attrs) do
    case new(attrs) do
      {:ok, report} ->
        report

      {:error, reason} ->
        raise ArgumentError, "invalid fitness dataset report: #{inspect(reason)}"
    end
  end

  @spec to_map(struct()) :: map()
  def to_map(%__MODULE__{} = report), do: Map.from_struct(report)

  defp validate_fields(attrs) do
    missing = Enum.reject(@fields, &Map.has_key?(attrs, &1))
    if missing == [], do: :ok, else: {:error, {:missing_fields, missing}}
  end

  defp validate_counts(attrs) do
    count_fields = [:record_count, :positive_count, :neutral_count, :negative_count]

    if Enum.all?(count_fields, &(is_integer(Map.get(attrs, &1)) and Map.get(attrs, &1) >= 0)),
      do: :ok,
      else: {:error, :invalid_counts}
  end

  defp validate_status(%{dataset_status: status})
       when status in [
              "invalid",
              "calibration_only",
              "replay_ready",
              "training_ready",
              "candidate_eval_ready"
            ],
       do: :ok

  defp validate_status(%{dataset_status: status}),
    do: {:error, {:invalid_dataset_status, status}}
end
