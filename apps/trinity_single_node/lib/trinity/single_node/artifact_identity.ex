defmodule Trinity.SingleNode.ArtifactIdentity do
  @moduledoc """
  Resolves stable runtime/artifact identity from the artifact on disk.

  Trace provenance must describe the artifact actually supplied to the
  runtime. Profile names are only fallback context; the adapted artifact
  manifest and pin are the primary source of Qwen/Sakana identity.
  """

  @qwen_model_id "Qwen/Qwen3-0.6B"
  @mock_model_id "trinity/mock-tiny-route-runtime"
  @qwen_adapter_id :trinity_qwen3_0_6b_sakana
  @mock_adapter_id :mock_tiny

  @spec resolve(atom(), String.t() | nil, keyword()) :: map()
  def resolve(runtime_profile, artifact_root, opts \\ [])

  def resolve(:mock_tiny, artifact_root, opts) do
    %{
      name: :mock_tiny,
      adapter_id: @mock_adapter_id,
      model_id: opt(opts, :model_id, @mock_model_id),
      artifact_ref: opt(opts, :artifact_ref, "artifact:mock-tiny-route-runtime"),
      artifact_repo: opt(opts, :artifact_repo),
      artifact_revision: opt(opts, :artifact_revision),
      artifact_manifest_sha256: opt(opts, :artifact_manifest_sha256),
      artifact_root: artifact_root,
      artifact_status: :mock,
      artifact_runtime?: false,
      qwen_loaded?: false,
      router_head_shape: opt(opts, :router_head_shape, [10, 8]),
      selected_tensor_count: opt(opts, :selected_tensor_count, 0),
      scale_offset_count: opt(opts, :scale_offset_count, 0),
      source_vector_shape: opt(opts, :source_vector_shape, [])
    }
  end

  def resolve(runtime_profile, artifact_root, opts) do
    root = artifact_root && Path.expand(artifact_root)
    manifest_path = root && Path.join(root, "manifest.json")

    case load_json(manifest_path) do
      {:ok, manifest} ->
        pin = load_pin(root, opts)

        manifest
        |> identity_from_manifest(runtime_profile, root, manifest_path, pin, opts)
        |> apply_overrides(opts)

      {:error, :missing} ->
        missing_identity(runtime_profile, root, manifest_path, opts)
        |> apply_overrides(opts)

      {:error, reason} ->
        missing_identity(runtime_profile, root, manifest_path, opts)
        |> Map.put(:artifact_status, {:invalid_manifest, reason})
        |> apply_overrides(opts)
    end
  end

  defp identity_from_manifest(manifest, runtime_profile, root, manifest_path, pin, opts) do
    model_id = string_field(manifest, "base_model_repo") || string_field(manifest, "model_id")
    qwen_loaded? = model_id == @qwen_model_id

    %{
      name: runtime_profile,
      adapter_id: if(qwen_loaded?, do: @qwen_adapter_id, else: nil),
      model_id: model_id,
      artifact_ref:
        opt(opts, :artifact_ref) || default_artifact_ref(qwen_loaded?, root, runtime_profile),
      artifact_repo: string_field(pin, "repo_id"),
      artifact_revision: string_field(pin, "revision"),
      artifact_manifest_sha256:
        string_field(pin, "manifest_sha256") || pinned_manifest_sha(pin) ||
          sha256_file(manifest_path),
      artifact_root: root,
      artifact_status: :available,
      artifact_runtime?: true,
      qwen_loaded?: qwen_loaded?,
      router_head_shape:
        list_field(manifest, "router_head_shape") || routing_field(manifest, "head_shape"),
      selected_tensor_count:
        integer_field(manifest, "selected_tensor_count") ||
          count_list(manifest, "selected_tensors"),
      scale_offset_count:
        integer_field(manifest, "scale_offset_count") ||
          get_in(manifest, ["source_split", "scale_count"]),
      source_vector_shape: list_field(manifest, "source_vector_shape")
    }
  end

  defp missing_identity(runtime_profile, root, manifest_path, opts) do
    %{
      name: runtime_profile,
      adapter_id: nil,
      model_id: opt(opts, :model_id),
      artifact_ref:
        opt(opts, :artifact_ref) || default_artifact_ref(false, root, runtime_profile),
      artifact_repo: opt(opts, :artifact_repo),
      artifact_revision: opt(opts, :artifact_revision),
      artifact_manifest_sha256: opt(opts, :artifact_manifest_sha256),
      artifact_root: root,
      artifact_manifest_path: manifest_path,
      artifact_status: :missing,
      artifact_runtime?: false,
      qwen_loaded?: false,
      router_head_shape: opt(opts, :router_head_shape),
      selected_tensor_count: opt(opts, :selected_tensor_count),
      scale_offset_count: opt(opts, :scale_offset_count),
      source_vector_shape: opt(opts, :source_vector_shape)
    }
  end

  defp apply_overrides(identity, opts) do
    [
      :adapter_id,
      :model_id,
      :artifact_ref,
      :artifact_repo,
      :artifact_revision,
      :artifact_manifest_sha256,
      :router_head_shape,
      :selected_tensor_count,
      :scale_offset_count,
      :source_vector_shape
    ]
    |> Enum.reduce(identity, fn key, acc ->
      case Keyword.fetch(opts, key) do
        {:ok, value} -> Map.put(acc, key, value)
        :error -> acc
      end
    end)
    |> refresh_capabilities()
  end

  defp refresh_capabilities(identity) do
    qwen_loaded? = identity.model_id == @qwen_model_id

    identity
    |> Map.put(:qwen_loaded?, qwen_loaded?)
    |> Map.put(
      :adapter_id,
      identity.adapter_id || if(qwen_loaded?, do: @qwen_adapter_id, else: nil)
    )
  end

  defp load_pin(nil, _opts), do: %{}

  defp load_pin(root, opts) do
    candidates =
      [
        opt(opts, :artifact_pin_path),
        opt(opts, :pin_path),
        Path.join(root, "artifact_pin.json"),
        Path.join(Path.dirname(root), "artifact_pin.json")
      ]
      |> Enum.reject(&is_nil/1)

    candidates
    |> Enum.find(&File.regular?/1)
    |> load_json()
    |> case do
      {:ok, pin} -> pin
      _other -> %{}
    end
  end

  defp load_json(nil), do: {:error, :missing}

  defp load_json(path) do
    if File.regular?(path) do
      case Jason.decode(File.read!(path)) do
        {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
        {:ok, _other} -> {:error, :invalid_json_shape}
        {:error, error} -> {:error, Exception.message(error)}
      end
    else
      {:error, :missing}
    end
  end

  defp default_artifact_ref(true, _root, _runtime_profile), do: "artifact:qwen3-0.6b-sakana"

  defp default_artifact_ref(false, root, runtime_profile) when is_binary(root) do
    "artifact:#{safe_fragment(Path.basename(root), Atom.to_string(runtime_profile))}"
  end

  defp default_artifact_ref(false, _root, runtime_profile),
    do: "artifact:#{Atom.to_string(runtime_profile)}"

  defp safe_fragment(value, fallback) do
    value
    |> to_string()
    |> String.graphemes()
    |> Enum.map_join(fn char ->
      if safe_ref_char?(char), do: char, else: "_"
    end)
    |> collapse_underscores()
    |> String.trim("_")
    |> case do
      "" -> fallback
      safe -> safe
    end
  end

  defp safe_ref_char?(<<char::utf8>>) do
    ascii_letter?(char) or ascii_digit?(char) or char in [45, 46, 58, 95]
  end

  defp safe_ref_char?(_char), do: false

  defp collapse_underscores(value), do: collapse_underscores(value, "", false)

  defp collapse_underscores("", acc, _previous?), do: acc

  defp collapse_underscores("_" <> rest, acc, true), do: collapse_underscores(rest, acc, true)

  defp collapse_underscores("_" <> rest, acc, false),
    do: collapse_underscores(rest, acc <> "_", true)

  defp collapse_underscores(<<char::utf8, rest::binary>>, acc, _previous?),
    do: collapse_underscores(rest, acc <> <<char::utf8>>, false)

  defp string_field(map, key) when is_map(map) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> value
      _other -> nil
    end
  end

  defp integer_field(map, key) when is_map(map) do
    case Map.get(map, key) do
      value when is_integer(value) -> value
      _other -> nil
    end
  end

  defp list_field(map, key) when is_map(map) do
    case Map.get(map, key) do
      value when is_list(value) -> value
      _other -> nil
    end
  end

  defp routing_field(manifest, key) do
    case get_in(manifest, ["python_semantic_manifest", "routing", key]) do
      value when is_list(value) -> value
      _other -> nil
    end
  end

  defp count_list(map, key) when is_map(map) do
    case Map.get(map, key) do
      value when is_list(value) -> length(value)
      _other -> nil
    end
  end

  defp pinned_manifest_sha(%{"files" => files}) when is_list(files) do
    Enum.find_value(files, fn
      %{"path" => "manifest.json", "sha256" => sha} when is_binary(sha) -> sha
      _other -> nil
    end)
  end

  defp pinned_manifest_sha(_pin), do: nil

  defp sha256_file(nil), do: nil

  defp sha256_file(path) do
    path
    |> File.read!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp opt(opts, key, default \\ nil), do: Keyword.get(opts, key, default)

  defp ascii_letter?(char), do: char in ?A..?Z or char in ?a..?z
  defp ascii_digit?(char), do: char in ?0..?9
end
