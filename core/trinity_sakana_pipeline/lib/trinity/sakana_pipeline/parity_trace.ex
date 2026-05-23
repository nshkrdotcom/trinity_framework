defmodule Trinity.SakanaPipeline.ParityTrace do
  @moduledoc """
  TRINITY Sakana parity-trace constants and JSON helpers.
  """

  alias Trinity.Sakana.StageName
  alias Trinity.SakanaPipeline.{LargeTensorChunks, PythonImporter}

  @router_vector_path "priv/sakana_trinity/artifacts/trinity_router_es_vector.safetensors"
  @reference_manifest_path "priv/sakana_trinity/reference/sakana_python_reference_manifest.json"
  @scale_count 9_216
  @hidden_size 1_024
  @output_count 10
  @component_file "trinity_svf_components.safetensors"
  @scale_file "trinity_svf_scale_offsets.safetensors"

  @spec router_vector_path() :: String.t()
  def router_vector_path, do: @router_vector_path

  @spec reference_manifest_path() :: String.t()
  def reference_manifest_path, do: @reference_manifest_path

  @spec scale_count() :: pos_integer()
  def scale_count, do: @scale_count

  @spec hidden_size() :: pos_integer()
  def hidden_size, do: @hidden_size

  @spec output_count() :: pos_integer()
  def output_count, do: @output_count

  @spec component_file() :: String.t()
  def component_file, do: @component_file

  @spec scale_file() :: String.t()
  def scale_file, do: @scale_file

  @spec stage_names() :: [String.t()]
  def stage_names, do: StageName.names()

  @spec tensor_stage_key(String.t(), String.t()) :: String.t()
  def tensor_stage_key(source_name, stage_name)
      when is_binary(source_name) and is_binary(stage_name) do
    "tensor.#{sanitize_python_key(source_name)}.#{stage_name}"
  end

  @spec semantic_layouts(map() | nil, boolean()) :: [:torch_v | :nx | :vh]
  def semantic_layouts(metadata, false), do: [preferred_layout(metadata)]

  def semantic_layouts(metadata, true) do
    metadata
    |> preferred_layout()
    |> then(&[&1, :torch_v, :nx, :vh])
    |> Enum.uniq()
  end

  @spec preferred_layout(map() | nil) :: :torch_v | :nx | :vh
  def preferred_layout(metadata) do
    metadata
    |> layout_from_metadata()
    |> case do
      nil -> :torch_v
      layout -> layout
    end
  end

  @spec backend_label_slug(term()) :: String.t()
  def backend_label_slug(backend) do
    backend
    |> inspect()
    |> String.downcase()
    |> collapse_non_alnum("_")
    |> String.trim("_")
  end

  @spec sanitize_python_key(String.t()) :: String.t()
  def sanitize_python_key(source_name) do
    LargeTensorChunks.sanitize_python_key(source_name)
  end

  @spec reference_selected_tensor_count(map() | nil) :: non_neg_integer()
  def reference_selected_tensor_count(nil), do: 0

  def reference_selected_tensor_count(reference) when is_map(reference) do
    reference
    |> Map.get("selected_tensors", [])
    |> length()
  end

  @spec reference_selected_singular_value_count(map() | nil) :: non_neg_integer()
  def reference_selected_singular_value_count(nil), do: 0

  def reference_selected_singular_value_count(reference) when is_map(reference) do
    reference
    |> Map.get("selected_tensors", [])
    |> Enum.reduce(0, fn entry, acc -> acc + Map.get(entry, "singular_values", 0) end)
  end

  defp layout_from_metadata(nil), do: nil

  defp layout_from_metadata(metadata) when is_map(metadata) do
    metadata
    |> Map.get("component_v_layout")
    |> PythonImporter.normalize_v_layout()
  end

  defp collapse_non_alnum(value, replacement) do
    {iodata, _in_replacement?} =
      value
      |> String.to_charlist()
      |> Enum.reduce({[], false}, fn char, {acc, in_replacement?} ->
        cond do
          alnum?(char) ->
            {[char | acc], false}

          in_replacement? ->
            {acc, true}

          true ->
            {[replacement | acc], true}
        end
      end)

    iodata
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defp alnum?(char), do: char in ?0..?9 or char in ?a..?z
end
