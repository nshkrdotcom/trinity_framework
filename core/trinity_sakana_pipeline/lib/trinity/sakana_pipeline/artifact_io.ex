defmodule Trinity.SakanaPipeline.ArtifactIO do
  @moduledoc """
  File, JSON, and SafeTensors helpers for Sakana pipeline artifacts.
  """

  alias CrucibleSafetensors.Reader
  alias CrucibleSafetensors.Writer
  alias Trinity.Sakana.Manifest

  @manifest_file "manifest.json"
  @router_head_file "router_head.safetensors"
  @router_head_tensor_key "trinity_router_head"
  @adapted_tensors_file "adapted_tensors.safetensors"
  @checkpoint_dir_name "checkpoints"
  @export_log_file "export.log.jsonl"

  @spec manifest_file() :: String.t()
  def manifest_file, do: @manifest_file

  @spec router_head_file() :: String.t()
  def router_head_file, do: @router_head_file

  @spec router_head_tensor_key() :: String.t()
  def router_head_tensor_key, do: @router_head_tensor_key

  @spec adapted_tensors_file() :: String.t()
  def adapted_tensors_file, do: @adapted_tensors_file

  @spec checkpoint_directory_name() :: String.t()
  def checkpoint_directory_name, do: @checkpoint_dir_name

  @spec export_log_file() :: String.t()
  def export_log_file, do: @export_log_file

  @spec manifest_path(Path.t()) :: Path.t()
  def manifest_path(out_dir), do: Path.join(out_dir, @manifest_file)

  @spec checkpoint_path(Path.t()) :: Path.t()
  def checkpoint_path(out_dir), do: Path.join(out_dir, @checkpoint_dir_name)

  @spec export_log_path(Path.t()) :: Path.t()
  def export_log_path(out_dir), do: Path.join(out_dir, @export_log_file)

  @spec load_json!(Path.t()) :: map() | list()
  def load_json!(path) when is_binary(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end

  @spec write_json!(Path.t(), term()) :: :ok
  def write_json!(path, value) when is_binary(path) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(normalize_json(value), pretty: true))
  end

  @spec load_manifest(Path.t()) :: {:ok, map()} | {:error, term()}
  def load_manifest(out_dir) when is_binary(out_dir) do
    with {:ok, body} <- File.read(manifest_path(out_dir)),
         {:ok, decoded} <- Jason.decode(body),
         {:ok, manifest} <- Manifest.validate(decoded) do
      {:ok, manifest}
    else
      {:error, :enoent} -> {:error, :missing_manifest}
      {:error, %Jason.DecodeError{} = error} -> {:error, {:invalid_manifest_json, error}}
      {:error, reason} -> {:error, reason}
    end
  end

  def load_manifest(_out_dir), do: {:error, :invalid_output_dir}

  @spec load_manifest!(Path.t()) :: map()
  def load_manifest!(out_dir) do
    case load_manifest(out_dir) do
      {:ok, manifest} -> manifest
      {:error, reason} -> raise ArgumentError, "unable to load manifest: #{inspect(reason)}"
    end
  end

  @spec write_manifest!(Path.t(), map()) :: :ok
  def write_manifest!(out_dir, manifest) when is_binary(out_dir) and is_map(manifest) do
    File.mkdir_p!(out_dir)
    write_json_atomic!(manifest_path(out_dir), manifest)
  end

  @spec write_json_atomic!(Path.t(), term()) :: :ok
  def write_json_atomic!(path, value) when is_binary(path) do
    tmp = path <> ".tmp"
    File.mkdir_p!(Path.dirname(path))
    File.write!(tmp, Jason.encode!(normalize_json(value)))
    File.rename!(tmp, path)
    :ok
  end

  @spec write_tensors!(Path.t(), %{String.t() => Nx.Tensor.t()}, keyword()) :: Path.t()
  def write_tensors!(path, tensors, opts \\ []) when is_binary(path) and is_map(tensors) do
    opts = Keyword.validate!(opts, metadata: %{})
    payloads = Map.new(tensors, fn {name, tensor} -> {name, tensor_payload!(tensor)} end)
    Writer.write!(payloads, path, metadata: opts[:metadata])
  end

  @spec read_tensors!(Path.t()) :: %{String.t() => Nx.Tensor.t()}
  def read_tensors!(path) when is_binary(path) do
    header = Reader.open!(path)

    header.tensors
    |> Enum.sort_by(fn {name, _info} -> name end)
    |> Map.new(fn {name, info} ->
      {name, tensor_from_slice!(read_tensor_slice!(header, info))}
    end)
  end

  @spec read_tensor!(Path.t(), String.t()) :: Nx.Tensor.t()
  def read_tensor!(path, key) when is_binary(path) and is_binary(key) do
    header = Reader.open!(path)
    info = Map.fetch!(header.tensors, key)
    tensor_from_slice!(read_tensor_slice!(header, info))
  end

  @spec file_sha256!(Path.t()) :: String.t()
  def file_sha256!(path) when is_binary(path) do
    File.open!(path, [:read, :binary], fn file ->
      file
      |> IO.binstream(1_048_576)
      |> Enum.reduce(:crypto.hash_init(:sha256), fn chunk, acc ->
        :crypto.hash_update(acc, chunk)
      end)
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)
    end)
  end

  @spec tensor_payload!(Nx.Tensor.t()) :: map()
  def tensor_payload!(%Nx.Tensor{} = tensor) do
    host = Nx.backend_transfer(tensor, Nx.BinaryBackend)

    %{
      dtype: writer_dtype!(Nx.type(host)),
      shape: host |> Nx.shape() |> Tuple.to_list(),
      data: Nx.to_binary(host)
    }
  end

  defp tensor_from_slice!(%CrucibleSafetensors.Slice{tensor: info, data: data}) do
    data
    |> Nx.from_binary(nx_dtype!(info.dtype))
    |> Nx.reshape(List.to_tuple(info.shape))
  end

  defp read_tensor_slice!(header, info) do
    case Reader.read_tensor(header, info) do
      {:ok, slice} -> slice
      {:error, exception} -> raise exception
    end
  end

  defp nx_dtype!(:f16), do: :f16
  defp nx_dtype!(:bf16), do: :bf16
  defp nx_dtype!(:f32), do: :f32
  defp nx_dtype!(:i32), do: :s32
  defp nx_dtype!(:i64), do: :s64

  defp writer_dtype!({:f, 16}), do: :f16
  defp writer_dtype!({:bf, 16}), do: :bf16
  defp writer_dtype!({:f, 32}), do: :f32
  defp writer_dtype!({:s, 32}), do: :i32
  defp writer_dtype!({:s, 64}), do: :i64
  defp writer_dtype!(type), do: raise(ArgumentError, "unsupported tensor dtype #{inspect(type)}")

  defp normalize_json(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {normalize_key(key), normalize_json(item)} end)
  end

  defp normalize_json(value) when is_list(value), do: Enum.map(value, &normalize_json/1)
  defp normalize_json(value) when is_tuple(value), do: Tuple.to_list(value)
  defp normalize_json(value) when is_boolean(value) or is_nil(value), do: value
  defp normalize_json(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_json(value), do: value

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: key
end
