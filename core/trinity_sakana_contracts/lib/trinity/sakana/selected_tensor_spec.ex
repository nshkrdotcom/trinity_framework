defmodule Trinity.Sakana.SelectedTensorSpec do
  @moduledoc """
  Contract for one adapted tensor entry in the Sakana artifact manifest.
  """

  @enforce_keys [:path, :artifact_key, :shape, :singular_values, :type]
  defstruct [:path, :artifact_key, :shape, :singular_values, :type, segments: [], metadata: %{}]

  @type t :: %__MODULE__{
          path: String.t(),
          artifact_key: String.t(),
          shape: [non_neg_integer()],
          singular_values: non_neg_integer(),
          type: String.t(),
          segments: [map()],
          metadata: map()
        }

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{} = attrs) do
    with {:ok, path} <- require_binary(attrs, "path"),
         {:ok, artifact_key} <- require_binary(attrs, "artifact_key"),
         {:ok, shape} <- require_integer_list(attrs, "shape"),
         {:ok, singular_values} <- require_non_neg_integer(attrs, "singular_values"),
         {:ok, type} <- require_binary(attrs, "type") do
      {:ok,
       %__MODULE__{
         path: path,
         artifact_key: artifact_key,
         shape: shape,
         singular_values: singular_values,
         type: type,
         segments: Map.get(attrs, "segments", []),
         metadata:
           Map.drop(attrs, [
             "path",
             "artifact_key",
             "shape",
             "singular_values",
             "type",
             "segments"
           ])
       }}
    end
  end

  def from_map(value), do: {:error, {:invalid_selected_tensor, value}}

  defp require_binary(attrs, key) do
    case Map.get(attrs, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      value -> {:error, {:invalid_selected_tensor_field, key, value}}
    end
  end

  defp require_integer_list(attrs, key) do
    case Map.get(attrs, key) do
      values when is_list(values) ->
        if Enum.all?(values, &(is_integer(&1) and &1 >= 0)) do
          {:ok, values}
        else
          {:error, {:invalid_selected_tensor_field, key, values}}
        end

      value ->
        {:error, {:invalid_selected_tensor_field, key, value}}
    end
  end

  defp require_non_neg_integer(attrs, key) do
    case Map.get(attrs, key) do
      value when is_integer(value) and value >= 0 -> {:ok, value}
      value -> {:error, {:invalid_selected_tensor_field, key, value}}
    end
  end
end
