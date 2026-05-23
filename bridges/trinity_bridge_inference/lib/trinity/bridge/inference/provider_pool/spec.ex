defmodule Trinity.Bridge.Inference.ProviderPool.Spec do
  @moduledoc "Typed provider spec normalization and validation."

  @known_providers [
    :openai,
    :openai_compatible,
    :gemini,
    :gemini_ex,
    :anthropic,
    :asm,
    :agent_session_manager,
    :mock
  ]
  @provider_by_name Map.new(@known_providers, &{Atom.to_string(&1), &1})

  @enforce_keys [:id, :provider, :model]
  defstruct [
    :id,
    :name,
    :provider,
    :model,
    :base_url,
    :timeout_ms,
    :max_tokens,
    :temperature,
    metadata: %{},
    enabled: true
  ]

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          name: atom() | String.t(),
          provider: atom(),
          model: String.t(),
          base_url: String.t() | nil,
          timeout_ms: pos_integer(),
          max_tokens: pos_integer(),
          temperature: float(),
          metadata: map(),
          enabled: boolean()
        }

  @spec normalize(list()) :: {:ok, [t()]} | {:error, term()}
  def normalize(raw) when is_list(raw), do: normalize_list(raw, [])
  def normalize(_raw), do: {:error, :invalid_pool}

  @spec normalize!(list()) :: [t()]
  def normalize!(raw) when is_list(raw) do
    case normalize(raw) do
      {:ok, pool} -> pool
      {:error, reason} -> raise ArgumentError, "invalid provider pool spec: #{inspect(reason)}"
    end
  end

  @spec validate([t()]) :: :ok | {:error, term()}
  def validate(pool) when is_list(pool) do
    with :ok <- validate_duplicate_ids(pool),
         :ok <- validate_duplicates(pool),
         :ok <- validate_contiguous_ids(pool) do
      validate_specs(pool)
    end
  end

  def validate(_pool), do: {:error, :invalid_pool}

  defp normalize_list([], acc), do: {:ok, Enum.sort_by(acc, & &1.id)}

  defp normalize_list([entry | rest], acc) do
    case normalize_entry(entry) do
      {:ok, spec} -> normalize_list(rest, [spec | acc])
      {:error, _reason} = error -> error
    end
  end

  defp normalize_entry(%__MODULE__{} = spec), do: normalize_struct(spec)

  defp normalize_entry(entry) when is_list(entry) or is_map(entry) do
    entry
    |> Map.new()
    |> build_spec()
  end

  defp normalize_entry(other), do: {:error, {:invalid_provider_entry, other}}

  defp build_spec(entry) do
    with {:ok, id} <- coerce_id(fetch(entry, :id)),
         {:ok, provider} <- coerce_provider(fetch(entry, :provider)),
         {:ok, model} <- coerce_non_empty_binary(fetch(entry, :model), :model),
         {:ok, timeout_ms} <- coalesce_positive_integer(fetch(entry, :timeout_ms), 30_000),
         {:ok, max_tokens} <- coalesce_positive_integer(fetch(entry, :max_tokens), 200),
         {:ok, temperature} <- coalesce_non_negative_number(fetch(entry, :temperature), 0.2),
         {:ok, name} <- normalize_name(fetch(entry, :name), id) do
      normalize_struct(%__MODULE__{
        id: id,
        name: name,
        provider: provider,
        model: model,
        base_url: coalesce_binary(fetch(entry, :base_url)),
        timeout_ms: timeout_ms,
        max_tokens: max_tokens,
        temperature: temperature,
        metadata: coalesce_map(fetch(entry, :metadata)),
        enabled: fetch(entry, :enabled, true)
      })
    end
  end

  defp normalize_struct(%__MODULE__{} = spec) do
    with {:ok, provider} <- coerce_provider(spec.provider),
         {:ok, model} <- coerce_non_empty_binary(spec.model, :model),
         {:ok, name} <- normalize_name(spec.name, spec.id) do
      {:ok, %{spec | provider: provider, model: model, name: name}}
    end
  end

  defp validate_duplicate_ids(pool) do
    ids = Enum.map(pool, & &1.id)
    unique = MapSet.new(ids)
    if MapSet.size(unique) == length(ids), do: :ok, else: {:error, :duplicate_provider_ids}
  end

  defp validate_duplicates(pool) do
    names = pool |> Enum.map(& &1.name) |> Enum.reject(&is_nil/1)
    unique = MapSet.new(names)
    if MapSet.size(unique) == length(names), do: :ok, else: {:error, :duplicate_provider_names}
  end

  defp validate_contiguous_ids(pool) do
    ids = pool |> Enum.map(& &1.id) |> Enum.sort()
    expected = Enum.to_list(0..(length(ids) - 1))
    if ids == expected, do: :ok, else: {:error, :non_contiguous_ids}
  end

  defp validate_specs(pool) do
    case Enum.find(pool, &invalid_openai_compatible?/1) do
      nil -> :ok
      invalid -> {:error, {:invalid_openai_compatible_spec, invalid}}
    end
  end

  defp invalid_openai_compatible?(%__MODULE__{provider: :openai_compatible, base_url: base_url}) do
    is_nil(base_url) or not is_binary(base_url)
  end

  defp invalid_openai_compatible?(_spec), do: false

  defp normalize_name(nil, id), do: {:ok, :"agent_#{id}"}
  defp normalize_name(name, _id) when is_atom(name), do: {:ok, name}
  defp normalize_name(name, _id) when is_binary(name), do: {:ok, name}

  defp coerce_id(id) when is_integer(id) and id >= 0, do: {:ok, id}
  defp coerce_id(id), do: {:error, {:invalid_provider_id, id}}

  defp coerce_provider(provider) when provider in @known_providers, do: {:ok, provider}

  defp coerce_provider(provider) when is_binary(provider),
    do: coerce_provider(@provider_by_name[provider])

  defp coerce_provider(provider), do: {:error, {:unsupported_provider, provider}}

  defp coerce_non_empty_binary(value, _field) when is_binary(value) and value != "",
    do: {:ok, value}

  defp coerce_non_empty_binary(value, field),
    do: {:error, {:invalid_binary_field, field, value}}

  defp coalesce_positive_integer(value, default) when is_nil(value), do: {:ok, default}

  defp coalesce_positive_integer(value, _default) when is_integer(value) and value > 0,
    do: {:ok, value}

  defp coalesce_positive_integer(value, _default),
    do: {:error, {:invalid_positive_integer, value}}

  defp coalesce_non_negative_number(value, default) when is_nil(value), do: {:ok, default}

  defp coalesce_non_negative_number(value, _default) when is_number(value) and value >= 0,
    do: {:ok, value}

  defp coalesce_non_negative_number(value, _default),
    do: {:error, {:invalid_non_negative_number, value}}

  defp coalesce_binary(value) when is_binary(value) and value != "", do: value
  defp coalesce_binary(_value), do: nil

  defp coalesce_map(value) when is_map(value), do: value
  defp coalesce_map(_value), do: %{}

  defp fetch(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, to_string(key), default))
end
