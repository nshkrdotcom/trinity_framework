defmodule Trinity.SakanaPipeline.LargeTensorChunks do
  @moduledoc """
  TRINITY-specific large tensor chunk planning for Sakana parity replay.
  """

  alias Trinity.Sakana.StageName

  @default_sources ["model.embed_tokens.weight", "lm_head.weight"]
  @default_chunk_rows 1024

  @spec default_sources() :: [String.t()]
  def default_sources, do: @default_sources

  @spec default_chunk_rows() :: pos_integer()
  def default_chunk_rows, do: @default_chunk_rows

  @spec stage_names() :: [String.t()]
  def stage_names, do: StageName.names()

  @spec large_source?(String.t()) :: boolean()
  def large_source?(source_name) when is_binary(source_name), do: source_name in @default_sources

  @spec chunk_plan(non_neg_integer(), keyword()) :: [map()]
  def chunk_plan(row_count, opts \\ []) when is_integer(row_count) and row_count >= 0 do
    opts = Keyword.validate!(opts, chunk_rows: @default_chunk_rows)
    chunks(row_count, positive_integer!(opts[:chunk_rows], :chunk_rows))
  end

  @spec chunks(non_neg_integer(), pos_integer()) :: [map()]
  def chunks(row_count, chunk_rows)
      when is_integer(row_count) and row_count >= 0 and is_integer(chunk_rows) and chunk_rows > 0 do
    row_count
    |> Stream.unfold(fn
      0 ->
        nil

      remaining ->
        row_start = row_count - remaining
        count = min(chunk_rows, remaining)
        row_end = row_start + count
        {%{"row_start" => row_start, "row_end" => row_end}, remaining - count}
    end)
    |> Enum.with_index(1)
    |> Enum.map(fn {chunk, index} -> Map.put(chunk, "chunk_index", index) end)
  end

  @spec baseline_plan(map(), keyword()) :: [map()]
  def baseline_plan(component_metadata, opts \\ []) when is_map(component_metadata) do
    opts = Keyword.validate!(opts, chunk_rows: @default_chunk_rows, sources: @default_sources)

    component_metadata
    |> Map.get("selected_tensors", [])
    |> Enum.filter(&(Map.get(&1, "source_name") in opts[:sources]))
    |> Enum.map(&baseline_entry(&1, opts[:chunk_rows]))
  end

  @spec summary([map()]) :: map()
  def summary(chunk_checks) when is_list(chunk_checks) do
    checks = Enum.flat_map(chunk_checks, &Map.get(&1, "checks", []))
    required = Enum.filter(checks, &Map.get(&1, "required_for_functional_parity"))
    failed = Enum.reject(required, &Map.get(&1, "functional_passed"))

    %{
      "chunk_count" => length(chunk_checks),
      "stage_check_count" => length(checks),
      "required_check_count" => length(required),
      "failed_required_count" => length(failed),
      "functional_parity_passed" => failed == []
    }
  end

  @spec sanitize_python_key(String.t()) :: String.t()
  def sanitize_python_key(source_name) when is_binary(source_name) do
    source_name
    |> String.replace("/", "__")
    |> replace_non_safe_path_chars("__")
  end

  defp baseline_entry(entry, chunk_rows) do
    row_count = entry |> Map.fetch!("shape") |> List.first()

    %{
      "source_name" => Map.fetch!(entry, "source_name"),
      "safe_key" =>
        Map.get(entry, "safe_key", sanitize_python_key(Map.fetch!(entry, "source_name"))),
      "shape" => Map.fetch!(entry, "shape"),
      "chunks" => chunks(row_count, chunk_rows)
    }
  end

  defp positive_integer!(value, _name) when is_integer(value) and value > 0, do: value

  defp positive_integer!(value, name),
    do: raise(ArgumentError, "#{name} must be positive, got #{inspect(value)}")

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
