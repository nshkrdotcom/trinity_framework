defmodule Trinity.Sakana.TraceFitnessReader do
  @moduledoc "Streaming JSONL reader for trace-derived fitness exports."

  @type entry :: %{path: String.t(), line: pos_integer(), record: map()}

  @spec read([String.t()], keyword()) ::
          {:ok, %{records: [entry()], skipped: [map()]}} | {:error, term()}
  def read(paths, opts \\ [])

  def read(paths, opts) when is_list(paths) and is_list(opts) do
    skip_invalid? = Keyword.get(opts, :skip_invalid, false)

    Enum.reduce_while(paths, {:ok, %{records: [], skipped: []}}, fn path, {:ok, acc} ->
      case read_path(path, skip_invalid?) do
        {:ok, result} ->
          {:cont,
           {:ok,
            %{
              records: acc.records ++ result.records,
              skipped: acc.skipped ++ result.skipped
            }}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  def read(_paths, _opts), do: {:error, :invalid_trace_paths}

  defp read_path(path, skip_invalid?) when is_binary(path) do
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
      {:error, {:trace_not_found, path}}
    end
  end

  defp read_path(path, _skip_invalid?), do: {:error, {:invalid_trace_path, path}}

  defp read_line(path, line_number, line, skip_invalid?, acc) do
    trimmed = String.trim(line)

    if trimmed == "",
      do: {:cont, {:ok, acc}},
      else: decode_line(path, line_number, trimmed, skip_invalid?, acc)
  end

  defp decode_line(path, line_number, line, skip_invalid?, acc) do
    case Jason.decode(line) do
      {:ok, record} when is_map(record) ->
        entry = %{path: path, line: line_number, record: record}
        {:cont, {:ok, %{acc | records: [entry | acc.records]}}}

      {:ok, _other} ->
        invalid_line(path, line_number, line, "JSON value is not an object", skip_invalid?, acc)

      {:error, error} ->
        invalid_line(path, line_number, line, Exception.message(error), skip_invalid?, acc)
    end
  end

  defp invalid_line(path, line_number, line, reason, true, acc) do
    skipped = %{
      path: path,
      line: line_number,
      reason: reason,
      line_hash: sha256(line)
    }

    {:cont, {:ok, %{acc | skipped: [skipped | acc.skipped]}}}
  end

  defp invalid_line(path, line_number, _line, reason, false, _acc),
    do: {:halt, {:error, {:invalid_json, path, line_number, reason}}}

  defp reverse_result({:ok, result}) do
    {:ok, %{records: Enum.reverse(result.records), skipped: Enum.reverse(result.skipped)}}
  end

  defp reverse_result(error), do: error

  defp sha256(value) do
    value
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
