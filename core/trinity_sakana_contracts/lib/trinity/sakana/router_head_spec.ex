defmodule Trinity.Sakana.RouterHeadSpec do
  @moduledoc """
  Sakana router-head shape contract.
  """

  @enforce_keys [:hidden_size, :num_agents, :num_roles]
  defstruct [
    :hidden_size,
    :num_agents,
    :num_roles,
    :router_head_shape,
    tensor_key: "trinity_router_head"
  ]

  @type t :: %__MODULE__{
          hidden_size: pos_integer(),
          num_agents: pos_integer(),
          num_roles: pos_integer(),
          router_head_shape: [pos_integer()] | nil,
          tensor_key: String.t()
        }

  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(%{} = attrs) do
    with {:ok, hidden_size} <- positive_integer(attrs, :hidden_size),
         {:ok, num_agents} <- positive_integer(attrs, :num_agents),
         {:ok, num_roles} <- positive_integer(attrs, :num_roles),
         {:ok, shape} <- shape(attrs, hidden_size, num_agents + num_roles) do
      {:ok,
       %__MODULE__{
         hidden_size: hidden_size,
         num_agents: num_agents,
         num_roles: num_roles,
         router_head_shape: shape,
         tensor_key: fetch(attrs, :tensor_key, "trinity_router_head")
       }}
    end
  end

  @spec output_count(t()) :: pos_integer()
  def output_count(%__MODULE__{} = spec), do: spec.num_agents + spec.num_roles

  defp shape(attrs, hidden_size, output_count) do
    case fetch(attrs, :router_head_shape, [output_count, hidden_size]) do
      [^output_count, ^hidden_size] = shape ->
        {:ok, shape}

      value ->
        {:error, {:invalid_router_head_shape, value, expected: [output_count, hidden_size]}}
    end
  end

  defp positive_integer(attrs, field) do
    case fetch(attrs, field) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      value -> {:error, {:invalid_positive_integer, field, value}}
    end
  end

  defp fetch(attrs, field, default \\ nil),
    do: Map.get(attrs, field, Map.get(attrs, Atom.to_string(field), default))
end
