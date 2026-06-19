defmodule Trinity.Sakana.FitnessManifest do
  @moduledoc "Manifest for a deterministic Sakana fitness dataset export."

  @schema_version "trinity.sakana.fitness_manifest.v1"
  @fields [
    :generated_at,
    :source_trace_paths,
    :record_count,
    :positive_count,
    :neutral_count,
    :negative_count,
    :skipped_count,
    :conflict_count,
    :score_formula,
    :score_formula_version,
    :margin_mode,
    :content_mode,
    :redaction_mode,
    :provenance_summary,
    :artifact_refs,
    :runtime_profiles,
    :route_hashes_digest,
    :dataset_digest
  ]

  @enforce_keys [:schema_version | @fields]
  defstruct @enforce_keys

  @type t :: %__MODULE__{}

  @spec schema_version() :: String.t()
  def schema_version, do: @schema_version

  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = Map.new(attrs)

    with :ok <- validate_fields(attrs),
         :ok <- validate_counts(attrs) do
      {:ok,
       struct!(__MODULE__, Map.put(Map.take(attrs, @fields), :schema_version, @schema_version))}
    end
  end

  def new(_attrs), do: {:error, :invalid_fitness_manifest}

  @spec new!(keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, manifest} -> manifest
      {:error, reason} -> raise ArgumentError, "invalid fitness manifest: #{inspect(reason)}"
    end
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = manifest), do: Map.from_struct(manifest)

  defp validate_fields(attrs) do
    missing = Enum.reject(@fields, &Map.has_key?(attrs, &1))
    if missing == [], do: :ok, else: {:error, {:missing_fields, missing}}
  end

  defp validate_counts(attrs) do
    counts =
      Enum.map(
        [
          :record_count,
          :positive_count,
          :neutral_count,
          :negative_count,
          :skipped_count,
          :conflict_count
        ],
        &Map.get(attrs, &1)
      )

    cond do
      not Enum.all?(counts, &(is_integer(&1) and &1 >= 0)) ->
        {:error, :invalid_counts}

      attrs.record_count != attrs.positive_count + attrs.neutral_count + attrs.negative_count ->
        {:error, :inconsistent_label_counts}

      true ->
        :ok
    end
  end
end
