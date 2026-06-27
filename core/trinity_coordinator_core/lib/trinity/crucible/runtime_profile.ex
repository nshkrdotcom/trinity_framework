defmodule Trinity.Crucible.RuntimeProfile do
  @moduledoc """
  Crucible-scoped runtime identity used by Trinity operator tap planning.
  """

  @derive Jason.Encoder
  defstruct name: :unknown,
            provider_kind: nil,
            model_id: nil,
            model_family: nil,
            backend: nil,
            artifact_ref: nil,
            artifact_root: nil,
            trajectory_layers: [],
            supported_capabilities: [],
            metadata: %{}

  @type t :: %__MODULE__{}

  @spec new(keyword() | map() | atom() | String.t() | nil) :: t()
  def new(nil), do: %__MODULE__{}
  def new(%__MODULE__{} = profile), do: profile
  def new(name) when is_atom(name) or is_binary(name), do: %__MODULE__{name: name}

  def new(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = attrs_map(attrs)

    %__MODULE__{
      name: field(attrs, :name, :unknown),
      provider_kind: field(attrs, :provider_kind),
      model_id: field(attrs, :model_id),
      model_family: field(attrs, :model_family),
      backend: field(attrs, :backend),
      artifact_ref: field(attrs, :artifact_ref),
      artifact_root: field(attrs, :artifact_root),
      trajectory_layers: normalize_list(field(attrs, :trajectory_layers, [])),
      supported_capabilities: normalize_list(field(attrs, :supported_capabilities, [])),
      metadata: field(attrs, :metadata, %{})
    }
  end

  @spec new!(keyword() | map() | atom() | String.t() | nil) :: t()
  def new!(attrs), do: new(attrs)

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = profile), do: Map.from_struct(profile)

  defp normalize_list(value) when is_list(value), do: value
  defp normalize_list(nil), do: []
  defp normalize_list(value), do: [value]

  defp attrs_map(attrs) when is_list(attrs), do: Map.new(attrs)
  defp attrs_map(attrs) when is_map(attrs), do: attrs

  defp field(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end
