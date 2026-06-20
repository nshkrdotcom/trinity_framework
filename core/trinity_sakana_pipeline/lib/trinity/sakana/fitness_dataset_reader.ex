defmodule Trinity.Sakana.FitnessDatasetReader do
  @moduledoc "Reader for exported Sakana fitness JSONL and manifest files."

  @type entry :: %{path: String.t(), line: pos_integer(), record: map()}

  @spec read(String.t(), keyword()) ::
          {:ok, %{records: [entry()], skipped: [map()]}} | {:error, term()}
  def read(path, opts \\ [])

  def read(path, opts) when is_binary(path) and is_list(opts) do
    skip_invalid? = Keyword.get(opts, :skip_invalid, false)

    if File.regular?(path) do
      path
      |> File.stream!(:line, [])
      |> Stream.with_index(1)
      |> Enum.reduce_while({:ok, %{records: [], skipped: []}}, fn {line, line_number},
                                                                  {:ok, acc} ->
        read_line(path, line_number, line, skip_invalid?, acc)
      end)
      |> reverse_result()
    else
      {:error, {:fitness_not_found, path}}
    end
  end

  def read(path, _opts), do: {:error, {:invalid_fitness_path, path}}

  @spec read_manifest(String.t() | nil) :: {:ok, map() | nil} | {:error, term()}
  def read_manifest(nil), do: {:ok, nil}

  def read_manifest(path) when is_binary(path) do
    if File.regular?(path) do
      case Jason.decode(File.read!(path)) do
        {:ok, manifest} when is_map(manifest) -> {:ok, manifest}
        {:ok, _other} -> {:error, {:invalid_manifest, path, "JSON value is not an object"}}
        {:error, error} -> {:error, {:invalid_manifest, path, Exception.message(error)}}
      end
    else
      {:error, {:manifest_not_found, path}}
    end
  end

  def read_manifest(path), do: {:error, {:invalid_manifest_path, path}}

  defp read_line(path, line_number, line, skip_invalid?, acc) do
    trimmed = String.trim(line)

    if trimmed == "",
      do: {:cont, {:ok, acc}},
      else: decode_line(path, line_number, trimmed, skip_invalid?, acc)
  end

  defp decode_line(path, line_number, line, skip_invalid?, acc) do
    case Jason.decode(line) do
      {:ok, record} when is_map(record) ->
        {:cont,
         {:ok, %{acc | records: [%{path: path, line: line_number, record: record} | acc.records]}}}

      {:ok, _other} ->
        invalid_line(path, line_number, line, "JSON value is not an object", skip_invalid?, acc)

      {:error, error} ->
        invalid_line(path, line_number, line, Exception.message(error), skip_invalid?, acc)
    end
  end

  defp invalid_line(path, line_number, _line, reason, false, _acc),
    do: {:halt, {:error, {:invalid_json, path, line_number, reason}}}

  defp invalid_line(path, line_number, line, reason, true, acc) do
    skipped = %{
      path: path,
      line: line_number,
      reason: reason,
      line_hash: digest(line)
    }

    {:cont, {:ok, %{acc | skipped: [skipped | acc.skipped]}}}
  end

  defp reverse_result({:ok, result}),
    do: {:ok, %{records: Enum.reverse(result.records), skipped: Enum.reverse(result.skipped)}}

  defp reverse_result(error), do: error

  defp digest(value) do
    "sha256:" <>
      (value
       |> then(&:crypto.hash(:sha256, &1))
       |> Base.encode16(case: :lower))
  end
end
