defmodule Trinity.Sakana.FitnessExample do
  @moduledoc "Schema-versioned, allowlisted route fitness example."

  @schema_version "trinity.sakana.fitness_example.v1"
  @map_fields [:source, :input, :route, :outcome, :fitness, :provenance]

  @enforce_keys [
    :schema_version,
    :example_id,
    :source,
    :input,
    :route,
    :outcome,
    :fitness,
    :provenance
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{}

  @spec schema_version() :: String.t()
  def schema_version, do: @schema_version

  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = Map.new(attrs)

    with {:ok, example_id} <- required_binary(attrs, :example_id),
         :ok <- validate_maps(attrs) do
      {:ok,
       %__MODULE__{
         schema_version: @schema_version,
         example_id: example_id,
         source: Map.fetch!(attrs, :source),
         input: Map.fetch!(attrs, :input),
         route: Map.fetch!(attrs, :route),
         outcome: Map.fetch!(attrs, :outcome),
         fitness: Map.fetch!(attrs, :fitness),
         provenance: Map.fetch!(attrs, :provenance)
       }}
    end
  end

  def new(_attrs), do: {:error, :invalid_fitness_example}

  @spec new!(keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, example} -> example
      {:error, reason} -> raise ArgumentError, "invalid fitness example: #{inspect(reason)}"
    end
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = example), do: Map.from_struct(example)

  defp validate_maps(attrs) do
    case Enum.find(@map_fields, &(not is_map(Map.get(attrs, &1)))) do
      nil -> :ok
      field -> {:error, {:invalid_field, field}}
    end
  end

  defp required_binary(attrs, field) do
    case Map.get(attrs, field) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _value -> {:error, {:invalid_field, field}}
    end
  end
end
