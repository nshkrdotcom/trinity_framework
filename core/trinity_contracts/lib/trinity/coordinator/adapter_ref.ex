defmodule Trinity.Coordinator.AdapterRef do
  @moduledoc """
  Stable runtime adapter identifier used at coordinator boundaries.
  """

  @enforce_keys [:id, :version, :contract]
  defstruct [:id, :version, :contract, metadata: %{}]

  @type key :: {atom(), String.t(), atom()}

  @type t :: %__MODULE__{
          id: atom(),
          version: String.t(),
          contract: atom(),
          metadata: map()
        }

  @spec new(keyword() | map() | t()) :: {:ok, t()} | {:error, term()}
  def new(%__MODULE__{} = adapter_ref), do: {:ok, adapter_ref}
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    with {:ok, id} <- require_atom(attrs, :id),
         {:ok, version} <- require_binary(attrs, :version),
         {:ok, contract} <- require_atom(attrs, :contract) do
      {:ok,
       %__MODULE__{
         id: id,
         version: version,
         contract: contract,
         metadata: fetch(attrs, :metadata, %{})
       }}
    end
  end

  def new(attrs), do: {:error, {:invalid_adapter_ref, attrs}}

  @spec new!(keyword() | map() | t()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, adapter_ref} -> adapter_ref
      {:error, reason} -> raise ArgumentError, "invalid adapter ref: #{inspect(reason)}"
    end
  end

  @spec key(t() | key()) :: key()
  def key(%__MODULE__{id: id, version: version, contract: contract}), do: {id, version, contract}
  def key({id, version, contract}), do: {id, version, contract}

  defp require_atom(attrs, field) do
    case fetch(attrs, field) do
      value when is_atom(value) -> {:ok, value}
      value -> {:error, {:invalid_atom_field, field, value}}
    end
  end

  defp require_binary(attrs, field) do
    case fetch(attrs, field) do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: {:error, {:blank_field, field}}, else: {:ok, value}

      value ->
        {:error, {:invalid_binary_field, field, value}}
    end
  end

  defp fetch(attrs, field, default \\ nil),
    do: Map.get(attrs, field, Map.get(attrs, Atom.to_string(field), default))
end
