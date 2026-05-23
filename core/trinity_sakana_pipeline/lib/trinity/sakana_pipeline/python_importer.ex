defmodule Trinity.SakanaPipeline.PythonImporter do
  @moduledoc """
  Normalization helpers for Sakana Python semantic-export manifests.
  """

  alias Trinity.SakanaPipeline.LargeTensorChunks

  @default_manifest "trinity_sakana_export_manifest.json"
  @default_components "trinity_svf_components.safetensors"
  @default_scales "trinity_svf_scale_offsets.safetensors"
  @default_head "trinity_router_head.safetensors"
  @python_head_key "trinity.router_head.linear.weight"

  @fallback_mapping %{
    "model.embed_tokens.weight" => "embedder.token_embedding.kernel",
    "model.layers.26.input_layernorm.weight" => "decoder.blocks.26.attention_norm.scale",
    "model.layers.26.post_attention_layernorm.weight" => "decoder.blocks.26.ffn_norm.scale",
    "model.layers.26.mlp.gate_proj.weight" => "decoder.blocks.26.ffn.gate.kernel",
    "model.layers.26.mlp.up_proj.weight" => "decoder.blocks.26.ffn.up.kernel",
    "model.layers.26.mlp.down_proj.weight" => "decoder.blocks.26.ffn.down.kernel",
    "model.layers.26.self_attn.q_norm.weight" => "decoder.blocks.26.attention.q_norm.scale",
    "model.layers.26.self_attn.k_norm.weight" => "decoder.blocks.26.attention.k_norm.scale",
    "lm_head.weight" => "language_modeling_head.output.kernel"
  }

  @spec default_manifest() :: String.t()
  def default_manifest, do: @default_manifest

  @spec default_components() :: String.t()
  def default_components, do: @default_components

  @spec default_scales() :: String.t()
  def default_scales, do: @default_scales

  @spec default_head() :: String.t()
  def default_head, do: @default_head

  @spec python_head_key() :: String.t()
  def python_head_key, do: @python_head_key

  @spec fallback_mapping() :: %{String.t() => String.t()}
  def fallback_mapping, do: @fallback_mapping

  @spec normalize_selected_entries(map(), map() | nil) :: [map()]
  def normalize_selected_entries(python_manifest, reference_manifest \\ nil)
      when is_map(python_manifest) do
    reference_by_source = reference_mapping(reference_manifest)

    python_manifest
    |> Map.get("selected_tensors", [])
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, index} ->
      normalize_selected_entry(entry, index, reference_by_source)
    end)
  end

  @spec component_keys(map()) :: map()
  def component_keys(entry) when is_map(entry) do
    safe_key = Map.get(entry, "safe_key", safe_key(source_name(entry)))
    components = Map.get(entry, "component_tensors", %{})

    %{
      "u" => component_key(components, "U", "u", "svd.U.#{safe_key}"),
      "s" => component_key(components, "S", "s", "svd.S.#{safe_key}"),
      "v" => component_key(components, "V", "v", "svd.V.#{safe_key}"),
      "scale_offsets" => Map.get(entry, "scale_tensor", "svf.scale_offsets.#{safe_key}")
    }
  end

  @spec provenance_path(Path.t() | nil, Path.t()) :: String.t() | nil
  def provenance_path(nil, _repo_root), do: nil

  def provenance_path(path, repo_root) when is_binary(path) and is_binary(repo_root) do
    expanded = Path.expand(path)
    root = Path.expand(repo_root)

    cond do
      Path.type(path) != :absolute ->
        path

      expanded == root ->
        "."

      String.starts_with?(expanded, root <> "/") ->
        Path.relative_to(expanded, root)

      true ->
        "<external>:#{Path.basename(path)}"
    end
  end

  @spec normalize_v_layout(term()) :: :torch_v | :vh | :nx | nil
  def normalize_v_layout("torch_v"), do: :torch_v
  def normalize_v_layout("torch-v"), do: :torch_v
  def normalize_v_layout("torch"), do: :torch_v
  def normalize_v_layout("vh"), do: :vh
  def normalize_v_layout("nx"), do: :nx
  def normalize_v_layout(:torch_v), do: :torch_v
  def normalize_v_layout(:vh), do: :vh
  def normalize_v_layout(:nx), do: :nx
  def normalize_v_layout(_other), do: nil

  defp normalize_selected_entry(entry, index, reference_by_source) when is_map(entry) do
    source = source_name(entry)
    reference = Map.get(reference_by_source, source, %{})
    path = selected_elixir_name(entry, reference, source)
    shape = selected_entry_shape(entry, reference)
    singular_values = Map.get(entry, "singular_values", Enum.min(shape))
    safe_key = Map.get(entry, "safe_key", safe_key(source))

    %{
      "index" => index,
      "source_name" => source,
      "path" => path,
      "artifact_key" => path,
      "safe_key" => safe_key,
      "shape" => shape,
      "singular_values" => singular_values,
      "offset_start" => Map.get(entry, "offset_start"),
      "offset_end" => Map.get(entry, "offset_end"),
      "component_tensors" => component_keys(Map.put(entry, "safe_key", safe_key)),
      "scale_tensor" => Map.get(entry, "scale_tensor", "svf.scale_offsets.#{safe_key}"),
      "python_v_layout" => Map.get(entry, "python_v_layout", "torch_v"),
      "target_verified" => false
    }
  end

  defp normalize_selected_entry(other, index, _reference_by_source) do
    raise ArgumentError, "invalid selected_tensors entry #{index}: #{inspect(other)}"
  end

  defp reference_mapping(nil), do: %{}

  defp reference_mapping(reference) when is_map(reference) do
    reference
    |> Map.get("selected_tensors", [])
    |> Map.new(fn entry ->
      {Map.get(entry, "source_name", Map.get(entry, "python_name")), entry}
    end)
  end

  defp selected_elixir_name(entry, reference, source) do
    Map.get(entry, "elixir_name") ||
      Map.get(entry, "path") ||
      Map.get(reference, "path") ||
      Map.get(@fallback_mapping, source, source)
  end

  defp selected_entry_shape(entry, reference) do
    Map.get(entry, "elixir_shape") ||
      Map.get(entry, "shape") ||
      Map.get(reference, "shape") ||
      raise(ArgumentError, "missing shape for selected tensor #{inspect(source_name(entry))}")
  end

  defp source_name(entry) do
    Map.get(entry, "source_name") ||
      Map.get(entry, "source") ||
      Map.get(entry, "python_name") ||
      Map.get(entry, "path") ||
      raise(ArgumentError, "missing source_name in Python selected tensor entry")
  end

  defp component_key(components, uppercase_key, lowercase_key, fallback) do
    Map.get(components, uppercase_key) || Map.get(components, lowercase_key) || fallback
  end

  defp safe_key(source_name), do: LargeTensorChunks.sanitize_python_key(source_name)
end
