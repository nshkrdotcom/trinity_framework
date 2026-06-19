defmodule Trinity.SingleNode.ArtifactIdentity do
  @moduledoc """
  Resolves stable runtime/artifact identity from the artifact on disk.

  Trace provenance must describe the artifact supplied to the executed runtime.
  Profile names are only fallback context; the adapted artifact manifest and
  pin are the primary source of Qwen/Sakana identity.
  """

  alias Trinity.RefSanitizer

  @qwen_model_id "Qwen/Qwen3-0.6B"
  @mock_model_id "trinity/mock-tiny-route-runtime"
  @qwen_adapter_id :trinity_qwen3_0_6b_sakana
  @mock_adapter_id :mock_tiny
  @canonical_qwen_repo "nshkrdotcom/trinity-coordinator-adapted-qwen3-0.6b"
  @canonical_qwen_revision "v1.0.0"

  @provenance_override_keys [
    :adapter_id,
    :manifest_status,
    :artifact_layout,
    :router_head_artifact,
    :router_head_shape,
    :selected_tensor_count,
    :scale_offset_count,
    :source_vector_shape
  ]

  @identity_expectation_keys [:model_id, :artifact_ref, :artifact_repo, :artifact_revision]

  @spec resolve(atom(), String.t() | nil, keyword()) :: map()
  def resolve(runtime_profile, artifact_root, opts \\ [])

  def resolve(:mock_tiny, artifact_root, _opts) do
    %{
      name: :mock_tiny,
      adapter_id: @mock_adapter_id,
      model_id: @mock_model_id,
      artifact_ref: "artifact:mock-tiny-route-runtime",
      artifact_repo: nil,
      artifact_revision: nil,
      artifact_manifest_sha256: nil,
      artifact_manifest_sha256_actual: nil,
      artifact_pin_manifest_sha256: nil,
      artifact_manifest_path: nil,
      artifact_pin_path: nil,
      artifact_root: artifact_root,
      artifact_status: :mock,
      artifact_status_reason: nil,
      manifest_status: nil,
      artifact_layout: nil,
      router_head_artifact: nil,
      artifact_available?: false,
      artifact_runtime?: false,
      artifact_pin_verified?: false,
      qwen_base_model?: false,
      sakana_route_artifact?: false,
      runtime_loaded?: false,
      executed_runtime?: false,
      qwen_loaded?: false,
      router_head_shape: [10, 8],
      selected_tensor_count: 0,
      scale_offset_count: 0,
      source_vector_shape: []
    }
  end

  def resolve(runtime_profile, artifact_root, opts) do
    root = artifact_root && Path.expand(artifact_root)
    manifest_path = root && Path.join(root, "manifest.json")

    case load_json(manifest_path) do
      {:ok, manifest} ->
        {pin, pin_path} = load_pin(root, opts)

        identity_from_manifest(manifest, runtime_profile, root, manifest_path, pin, pin_path)

      {:error, :missing} ->
        missing_identity(runtime_profile, root, manifest_path)

      {:error, reason} ->
        missing_identity(runtime_profile, root, manifest_path)
        |> Map.merge(%{
          artifact_status: :invalid_manifest,
          artifact_status_reason: to_string(reason)
        })
    end
  end

  @doc """
  Rejects caller options that attempt to replace artifact-derived provenance.

  Identity label options are assertions: they are accepted only when they
  match the resolved identity. Artifact structure and capability fields are
  never caller-configurable.
  """
  @spec validate_request(map(), keyword()) :: :ok | {:error, term()}
  def validate_request(identity, opts) when is_map(identity) and is_list(opts) do
    with :ok <- validate_options(opts) do
      validate_expectations(identity, opts)
    end
  end

  @spec validate_options(keyword()) :: :ok | {:error, term()}
  def validate_options(opts) when is_list(opts) do
    keys = Enum.filter(@provenance_override_keys, &Keyword.has_key?(opts, &1))

    if keys == [], do: :ok, else: {:error, {:invalid_artifact_identity_options, keys}}
  end

  @spec validate_expectations(map(), keyword()) :: :ok | {:error, term()}
  def validate_expectations(identity, opts) when is_map(identity) and is_list(opts) do
    Enum.reduce_while(@identity_expectation_keys, :ok, fn key, :ok ->
      actual = Map.get(identity, key)

      case Keyword.fetch(opts, key) do
        {:ok, expected} when expected != actual ->
          {:halt,
           {:error,
            {:artifact_identity_mismatch, %{reason: key, expected: expected, actual: actual}}}}

        _match_or_absent ->
          {:cont, :ok}
      end
    end)
  end

  @spec mark_loaded(map()) :: map()
  def mark_loaded(identity) when is_map(identity) do
    qwen_loaded? = qwen_route_ready?(identity)

    identity
    |> Map.put(:runtime_loaded?, true)
    |> Map.put(:executed_runtime?, true)
    |> Map.put(:qwen_loaded?, qwen_loaded?)
  end

  @spec qwen_route_ready?(map()) :: boolean()
  def qwen_route_ready?(identity) when is_map(identity) do
    identity.qwen_base_model? and identity.sakana_route_artifact? and identity.artifact_available? and
      identity.artifact_pin_verified?
  end

  defp identity_from_manifest(manifest, runtime_profile, root, manifest_path, pin, pin_path) do
    facts = manifest_facts(manifest)
    actual_sha = sha256_file(manifest_path)
    pin_sha = pin_manifest_sha(pin)
    {status, reason, pin_verified?} = artifact_status(pin_path, pin_sha, actual_sha)

    base_identity = %{
      name: runtime_profile,
      adapter_id: if(facts.sakana_route_artifact?, do: @qwen_adapter_id, else: nil),
      model_id: facts.model_id,
      artifact_repo: string_field(pin, "repo_id"),
      artifact_revision: string_field(pin, "revision"),
      artifact_manifest_sha256: actual_sha,
      artifact_manifest_sha256_actual: actual_sha,
      artifact_pin_manifest_sha256: pin_sha,
      artifact_manifest_path: manifest_path,
      artifact_pin_path: pin_path,
      artifact_root: root,
      artifact_status: status,
      artifact_status_reason: reason,
      manifest_status: facts.manifest_status,
      artifact_layout: facts.artifact_layout,
      router_head_artifact: facts.router_head_artifact,
      artifact_available?: artifact_available_status?(status),
      artifact_runtime?: artifact_available_status?(status),
      artifact_pin_verified?: pin_verified?,
      qwen_base_model?: facts.qwen_base_model?,
      sakana_route_artifact?: facts.sakana_route_artifact?,
      runtime_loaded?: false,
      executed_runtime?: false,
      qwen_loaded?: false,
      router_head_shape: facts.router_head_shape,
      selected_tensor_count: facts.selected_tensor_count,
      scale_offset_count: facts.scale_offset_count,
      source_vector_shape: facts.source_vector_shape
    }

    Map.put(
      base_identity,
      :artifact_ref,
      default_artifact_ref(base_identity, root, runtime_profile)
    )
  end

  defp missing_identity(runtime_profile, root, manifest_path) do
    %{
      name: runtime_profile,
      adapter_id: nil,
      model_id: nil,
      artifact_ref: default_missing_artifact_ref(root, runtime_profile),
      artifact_repo: nil,
      artifact_revision: nil,
      artifact_manifest_sha256: nil,
      artifact_manifest_sha256_actual: nil,
      artifact_pin_manifest_sha256: nil,
      artifact_manifest_path: manifest_path,
      artifact_pin_path: nil,
      artifact_root: root,
      artifact_status: :missing,
      artifact_status_reason: "manifest.json not found",
      manifest_status: nil,
      artifact_layout: nil,
      router_head_artifact: nil,
      artifact_available?: false,
      artifact_runtime?: false,
      artifact_pin_verified?: false,
      qwen_base_model?: false,
      sakana_route_artifact?: false,
      runtime_loaded?: false,
      executed_runtime?: false,
      qwen_loaded?: false,
      router_head_shape: nil,
      selected_tensor_count: nil,
      scale_offset_count: nil,
      source_vector_shape: nil
    }
  end

  defp manifest_facts(manifest) do
    model_id = string_field(manifest, "base_model_repo") || string_field(manifest, "model_id")

    router_head_shape =
      list_field(manifest, "router_head_shape") || routing_field(manifest, "head_shape")

    selected_tensor_count = selected_tensor_count(manifest)
    scale_offset_count = scale_offset_count(manifest)
    source_vector_shape = list_field(manifest, "source_vector_shape")
    qwen_base_model? = qwen_base_model?(model_id)
    manifest_status = string_field(manifest, "status")
    artifact_layout = string_field(manifest, "artifact_layout")
    router_head_artifact = string_field(manifest, "router_head_artifact")

    %{
      model_id: model_id,
      manifest_status: manifest_status,
      artifact_layout: artifact_layout,
      router_head_artifact: router_head_artifact,
      qwen_base_model?: qwen_base_model?,
      sakana_route_artifact?:
        sakana_route_artifact?(
          qwen_base_model?,
          manifest_status,
          artifact_layout,
          router_head_artifact,
          router_head_shape,
          selected_tensor_count,
          scale_offset_count,
          source_vector_shape
        ),
      router_head_shape: router_head_shape,
      selected_tensor_count: selected_tensor_count,
      scale_offset_count: scale_offset_count,
      source_vector_shape: source_vector_shape
    }
  end

  defp selected_tensor_count(manifest) do
    integer_field(manifest, "selected_tensor_count") || count_list(manifest, "selected_tensors")
  end

  defp scale_offset_count(manifest) do
    integer_field(manifest, "scale_offset_count") ||
      integer_field(manifest, "selected_singular_value_count") ||
      get_in(manifest, ["source_split", "scale_count"])
  end

  defp qwen_base_model?(model_id), do: model_id == @qwen_model_id

  defp sakana_route_artifact?(
         qwen_base_model?,
         manifest_status,
         artifact_layout,
         router_head_artifact,
         router_head_shape,
         selected_tensor_count,
         scale_offset_count,
         source_vector_shape
       ) do
    qwen_base_model? and manifest_status == "complete" and
      known_artifact_layout?(artifact_layout) and present_string?(router_head_artifact) and
      router_head_shape == [10, 1024] and
      positive_integer?(selected_tensor_count) and
      positive_integer?(scale_offset_count) and non_empty_list?(source_vector_shape)
  end

  defp artifact_available_status?(status), do: status in [:available, :available_unpinned]

  defp load_pin(nil, _opts), do: {%{}, nil}

  defp load_pin(root, opts) do
    candidates =
      [
        Keyword.get(opts, :artifact_pin_path),
        Keyword.get(opts, :pin_path),
        Path.join(root, "artifact_pin.json"),
        Path.join(Path.dirname(root), "artifact_pin.json")
      ]
      |> Enum.reject(&is_nil/1)

    with path when is_binary(path) <- Enum.find(candidates, &File.regular?/1),
         {:ok, pin} <- load_json(path) do
      {pin, path}
    else
      _other -> {%{}, nil}
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

  defp artifact_status(nil, nil, _actual_sha),
    do: {:available_unpinned, "artifact pin not found", false}

  defp artifact_status(_pin_path, nil, _actual_sha),
    do: {:pin_missing, "artifact pin does not include manifest sha256", false}

  defp artifact_status(_pin_path, pin_sha, actual_sha) when pin_sha == actual_sha,
    do: {:available, nil, true}

  defp artifact_status(_pin_path, _pin_sha, _actual_sha),
    do: {:pin_mismatch, "artifact pin manifest sha256 does not match manifest.json", false}

  defp default_artifact_ref(identity, root, runtime_profile) do
    cond do
      canonical_qwen_artifact?(identity) ->
        "artifact:qwen3-0.6b-sakana"

      identity.artifact_repo && identity.artifact_revision &&
          identity.artifact_manifest_sha256_actual ->
        repo =
          RefSanitizer.safe_fragment(identity.artifact_repo, allow_colon?: false, trim?: true)

        revision =
          RefSanitizer.safe_fragment(identity.artifact_revision, allow_colon?: false, trim?: true)

        "artifact:#{repo}:#{revision}:#{short_sha(identity.artifact_manifest_sha256_actual)}"

      identity.artifact_manifest_sha256_actual ->
        base = root_fragment(root, runtime_profile)
        "artifact:#{base}:#{short_sha(identity.artifact_manifest_sha256_actual)}"

      true ->
        "artifact:#{root_fragment(root, runtime_profile)}"
    end
  end

  defp canonical_qwen_artifact?(identity) do
    identity.sakana_route_artifact? and identity.artifact_repo == @canonical_qwen_repo and
      identity.artifact_revision == @canonical_qwen_revision and identity.artifact_pin_verified?
  end

  defp default_missing_artifact_ref(root, runtime_profile) do
    "artifact:#{root_fragment(root, runtime_profile)}"
  end

  defp root_fragment(root, runtime_profile) when is_binary(root) do
    RefSanitizer.safe_fragment(Path.basename(root),
      fallback: Atom.to_string(runtime_profile),
      allow_colon?: false,
      trim?: true
    )
  end

  defp root_fragment(_root, runtime_profile), do: Atom.to_string(runtime_profile)

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

  defp pin_manifest_sha(%{"manifest_sha256" => sha}) when is_binary(sha) and sha != "", do: sha

  defp pin_manifest_sha(%{"files" => files}) when is_list(files) do
    Enum.find_value(files, fn
      %{"path" => "manifest.json", "sha256" => sha} when is_binary(sha) and sha != "" -> sha
      _other -> nil
    end)
  end

  defp pin_manifest_sha(_pin), do: nil

  defp sha256_file(nil), do: nil

  defp sha256_file(path) do
    path
    |> File.read!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp short_sha(nil), do: "unknown"
  defp short_sha(<<prefix::binary-size(12), _rest::binary>>), do: prefix
  defp short_sha(value), do: value

  defp positive_integer?(value), do: is_integer(value) and value > 0
  defp non_empty_list?(value), do: is_list(value) and value != []

  defp present_string?(value), do: is_binary(value) and value != ""

  defp known_artifact_layout?(layout) do
    layout in ["checkpoint_directory", "test_fixture", "trinity_sakana"]
  end
end
