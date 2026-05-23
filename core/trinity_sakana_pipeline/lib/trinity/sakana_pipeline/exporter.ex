defmodule Trinity.SakanaPipeline.Exporter do
  @moduledoc """
  TRINITY Sakana export manifest planning helpers.
  """

  alias CrucibleFactorization.Backend
  alias Trinity.Sakana.{Manifest, RouterHeadSpec, SLMProfileSpec}
  alias Trinity.SakanaPipeline.ArtifactIO

  @checkpoint_name_width 4
  @complete_status "complete"
  @pending_status "pending"
  @partial_status "partial"
  @default_scale_offset_count 9_216

  @spec status_complete() :: String.t()
  def status_complete, do: @complete_status

  @spec status_pending() :: String.t()
  def status_pending, do: @pending_status

  @spec build_selected_tensors([map()], keyword()) :: [map()]
  def build_selected_tensors(selected, opts \\ []) when is_list(selected) do
    opts = Keyword.validate!(opts, svd_compute_type: :source, backend_label: nil)

    selected
    |> Enum.with_index(1)
    |> Enum.map_reduce(0, fn {entry, index}, cursor ->
      count = singular_count(entry)
      path = required_field!(entry, "path")
      tensor = required_field!(entry, "tensor")
      backend = opts[:backend_label] || Backend.label(tensor)

      item = %{
        "index" => index,
        "path" => path,
        "artifact_key" => field(entry, "artifact_key", path),
        "segments" => field(entry, "segments", []),
        "shape" => tensor |> Nx.shape() |> Tuple.to_list(),
        "type" => inspect(Nx.type(tensor)),
        "source_type" => inspect(Nx.type(tensor)),
        "svd_compute_type" => Atom.to_string(opts[:svd_compute_type]),
        "status" => @pending_status,
        "offset_start" => cursor,
        "offset_end" => cursor + count,
        "singular_values" => count,
        "checkpoint_path" =>
          Path.join(ArtifactIO.checkpoint_directory_name(), checkpoint_file(index, path)),
        "backend_observed_during_export" => backend,
        "decompose_elapsed_ms" => nil,
        "reconstruct_elapsed_ms" => nil,
        "u_backend" => nil,
        "s_backend" => nil,
        "v_backend" => nil,
        "adapted_backend" => nil,
        "error" => nil,
        "checkpoint_sha256" => nil
      }

      {item, cursor + count}
    end)
    |> elem(0)
  end

  @spec manifest_seed(keyword()) :: map()
  def manifest_seed(opts) when is_list(opts) do
    opts =
      Keyword.validate!(opts,
        profile: SLMProfileSpec.qwen3_0_6b_layer26(),
        router_head: default_router_head_spec(),
        selected: [],
        source_vector_shape: nil,
        source_vector_sha256: nil,
        source_vector_path: nil,
        source_vector_tensor: "trinity_router_es_vector",
        scale_offset_count: @default_scale_offset_count,
        source_split: nil,
        split: nil,
        svd_compute_type: :source,
        now: &DateTime.utc_now/0
      )

    profile = opts[:profile]
    router_head = opts[:router_head]
    selected = build_selected_tensors(opts[:selected], svd_compute_type: opts[:svd_compute_type])
    now = opts[:now].() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    output_count = RouterHeadSpec.output_count(router_head)
    scale_offset_count = opts[:scale_offset_count]

    %{
      "artifact_version" => Manifest.manifest_version(),
      "status" => @pending_status,
      "created_at" => now,
      "updated_at" => now,
      "base_model_repo" => profile.base_model_repo,
      "architecture" => "for_causal_language_modeling",
      "xla_target" => "cuda12",
      "export_backend" => "elixir_nx_exla_cuda",
      "source_vector_path" => opts[:source_vector_path],
      "source_vector_tensor" => opts[:source_vector_tensor],
      "source_vector_shape" => opts[:source_vector_shape],
      "source_vector_sha256" => opts[:source_vector_sha256],
      "scale_offset_count" => scale_offset_count,
      "router_head_shape" => router_head.router_head_shape,
      "router_head_artifact" => ArtifactIO.router_head_file(),
      "router_head_tensor_key" => ArtifactIO.router_head_tensor_key(),
      "adapted_tensors_artifact" => ArtifactIO.adapted_tensors_file(),
      "artifact_layout" => Manifest.artifact_layout_checkpoint_directory(),
      "selected_tensor_count" => length(selected),
      "selected_singular_value_count" => selected_singular_value_count(selected),
      "export_complete" => false,
      "selected_tensors" => selected,
      "source_split" =>
        opts[:source_split] ||
          %{
            "scale_count" => scale_offset_count,
            "hidden_size" => profile.hidden_size,
            "output_count" => output_count
          },
      "split" =>
        opts[:split] ||
          %{
            "scale_count" => scale_offset_count,
            "head_count" => output_count * profile.hidden_size
          }
    }
  end

  @spec finalize_manifest(map()) :: map()
  def finalize_manifest(manifest) when is_map(manifest) do
    if all_tensors_complete?(Map.get(manifest, "selected_tensors", [])) do
      manifest
      |> Map.put("status", @complete_status)
      |> Map.put("export_complete", true)
    else
      manifest
      |> Map.put("status", @partial_status)
      |> Map.put("export_complete", false)
    end
  end

  @spec all_tensors_complete?([map()]) :: boolean()
  def all_tensors_complete?(entries) when is_list(entries) do
    entries != [] and Enum.all?(entries, &(Map.get(&1, "status") == @complete_status))
  end

  @spec checkpoint_file(pos_integer(), String.t()) :: String.t()
  def checkpoint_file(index, path) when is_integer(index) and index > 0 and is_binary(path) do
    idx = index |> Integer.to_string() |> String.pad_leading(@checkpoint_name_width, "0")
    "#{idx}_#{replace_non_safe_path_chars(path, "_")}.safetensors"
  end

  @spec selected_singular_value_count([map()]) :: non_neg_integer()
  def selected_singular_value_count(entries) when is_list(entries) do
    Enum.reduce(entries, 0, &(&2 + Map.fetch!(&1, "singular_values")))
  end

  @spec sync_tensor!(Nx.Tensor.t()) :: Nx.Tensor.t()
  def sync_tensor!(%Nx.Tensor{} = tensor) do
    _ = tensor |> Nx.sum() |> Nx.to_number()
    tensor
  end

  defp singular_count(entry) do
    case field(entry, "singular_values") do
      count when is_integer(count) and count >= 0 ->
        count

      nil ->
        entry
        |> required_field!("tensor")
        |> Nx.shape()
        |> Tuple.to_list()
        |> Enum.min()
    end
  end

  defp default_router_head_spec do
    {:ok, spec} =
      RouterHeadSpec.new(
        hidden_size: 1_024,
        num_agents: 7,
        num_roles: 3,
        router_head_shape: [10, 1_024]
      )

    spec
  end

  defp required_field!(entry, key) do
    field(entry, key) || raise ArgumentError, "missing selected tensor field #{inspect(key)}"
  end

  defp field(entry, key, default \\ nil)
  defp field(entry, "path", default), do: Map.get(entry, "path", Map.get(entry, :path, default))

  defp field(entry, "tensor", default),
    do: Map.get(entry, "tensor", Map.get(entry, :tensor, default))

  defp field(entry, "segments", default),
    do: Map.get(entry, "segments", Map.get(entry, :segments, default))

  defp field(entry, "artifact_key", default),
    do: Map.get(entry, "artifact_key", Map.get(entry, :artifact_key, default))

  defp field(entry, "singular_values", default),
    do: Map.get(entry, "singular_values", Map.get(entry, :singular_values, default))

  defp replace_non_safe_path_chars(value, replacement) do
    value
    |> String.to_charlist()
    |> Enum.map(fn char ->
      if safe_path_char?(char), do: char, else: replacement
    end)
    |> IO.iodata_to_binary()
  end

  defp safe_path_char?(char) do
    (char >= ?0 and char <= ?9) or
      (char >= ?A and char <= ?Z) or
      (char >= ?a and char <= ?z) or
      char in [?-, ?_, ?.]
  end
end
