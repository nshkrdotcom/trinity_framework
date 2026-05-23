defmodule Trinity.Sakana.Manifest do
  @moduledoc """
  Sakana adapted artifact manifest schema and invariants.
  """

  alias Trinity.Sakana.{RouterHeadSpec, SelectedTensorSpec}

  @manifest_version 1
  @single_file "single_file"
  @checkpoint_directory "checkpoint_directory"

  @required_keys ~w(
    artifact_version
    status
    selected_tensors
    adapted_tensors_artifact
    router_head_artifact
    router_head_shape
    artifact_layout
    selected_tensor_count
    selected_singular_value_count
    source_vector_shape
    source_vector_sha256
    scale_offset_count
    router_head_tensor_key
    base_model_repo
    architecture
    xla_target
    export_backend
    source_vector_path
    source_vector_tensor
    export_complete
    source_split
    split
  )

  @spec manifest_version() :: 1
  def manifest_version, do: @manifest_version

  @spec required_keys() :: [String.t()]
  def required_keys, do: @required_keys

  @spec artifact_layout_single_file() :: String.t()
  def artifact_layout_single_file, do: @single_file

  @spec artifact_layout_checkpoint_directory() :: String.t()
  def artifact_layout_checkpoint_directory, do: @checkpoint_directory

  @spec validate(map()) :: {:ok, map()} | {:error, term()}
  def validate(%{} = manifest) do
    with :ok <- validate_required_keys(manifest),
         :ok <- validate_layout(manifest),
         {:ok, selected} <- selected_tensors(manifest),
         :ok <- validate_selected_count(manifest, selected),
         :ok <- validate_router_head(manifest) do
      {:ok, manifest}
    end
  end

  def validate(value), do: {:error, {:invalid_manifest, value}}

  @spec selected_tensors(map()) :: {:ok, [SelectedTensorSpec.t()]} | {:error, term()}
  def selected_tensors(%{} = manifest) do
    case Map.get(manifest, "selected_tensors") do
      entries when is_list(entries) ->
        parse_selected_tensors(entries)

      value ->
        {:error, {:invalid_selected_tensors, value}}
    end
  end

  defp validate_required_keys(manifest) do
    case Enum.find(@required_keys, &(not Map.has_key?(manifest, &1))) do
      nil -> :ok
      key -> {:error, {:missing_manifest_key, key}}
    end
  end

  defp validate_layout(manifest) do
    case Map.get(manifest, "artifact_layout") do
      layout when layout in [@single_file, @checkpoint_directory] -> :ok
      layout -> {:error, {:invalid_artifact_layout, layout}}
    end
  end

  defp validate_selected_count(manifest, selected) do
    expected = Map.get(manifest, "selected_tensor_count")

    if expected == length(selected) do
      :ok
    else
      {:error, {:selected_tensor_count_mismatch, expected: expected, actual: length(selected)}}
    end
  end

  defp parse_selected_tensors(entries) do
    entries
    |> Enum.reduce_while([], &parse_selected_tensor/2)
    |> finalize_selected_tensors()
  end

  defp parse_selected_tensor(entry, acc) do
    case SelectedTensorSpec.from_map(entry) do
      {:ok, spec} -> {:cont, [spec | acc]}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp finalize_selected_tensors({:error, reason}), do: {:error, reason}
  defp finalize_selected_tensors(specs), do: {:ok, Enum.reverse(specs)}

  defp validate_router_head(%{"router_head_shape" => [output_count, hidden_size]} = manifest)
       when is_integer(output_count) and is_integer(hidden_size) and output_count > 3 do
    RouterHeadSpec.new(
      hidden_size: hidden_size,
      num_agents: output_count - 3,
      num_roles: 3,
      router_head_shape: [output_count, hidden_size],
      tensor_key: Map.get(manifest, "router_head_tensor_key")
    )
    |> case do
      {:ok, _spec} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_router_head(manifest) do
    {:error, {:invalid_router_head_shape, Map.get(manifest, "router_head_shape")}}
  end
end
