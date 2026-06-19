defmodule Trinity.Sakana.FitnessJsonlWriter do
  @moduledoc "Writes canonical fitness JSONL and its dataset manifest."

  alias Trinity.Sakana.{FitnessExample, FitnessManifest}

  @spec write([FitnessExample.t()], keyword()) :: {:ok, map()} | {:error, term()}
  def write(examples, opts \\ []) when is_list(examples) and is_list(opts) do
    maps = Enum.map(examples, &example_map/1)
    dataset_bytes = Enum.map_join(maps, "", &(canonical_json(&1) <> "\n"))
    route_hashes = maps |> Enum.map(&get_in(&1, [:route, "route_hash"])) |> Enum.reject(&is_nil/1)
    manifest = build_manifest(maps, dataset_bytes, route_hashes, opts)
    dry_run? = Keyword.get(opts, :dry_run, false)

    with :ok <- maybe_write(Keyword.get(opts, :out), dataset_bytes, dry_run?),
         :ok <-
           maybe_write(
             manifest_path(opts),
             canonical_json(FitnessManifest.to_map(manifest)) <> "\n",
             dry_run?
           ),
         :ok <- maybe_write_report(opts, dry_run?) do
      {:ok, %{manifest: manifest, dataset_bytes: dataset_bytes}}
    end
  end

  defp build_manifest(maps, dataset_bytes, route_hashes, opts) do
    labels = Enum.frequencies_by(maps, &get_in(&1, [:fitness, "label"]))
    source_paths = Keyword.get(opts, :source_trace_paths, []) |> Enum.uniq() |> Enum.sort()

    FitnessManifest.new!(
      generated_at:
        Keyword.get_lazy(opts, :generated_at, fn ->
          DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
        end),
      source_trace_paths: source_paths,
      record_count: length(maps),
      positive_count: label_count(labels, :positive),
      neutral_count: label_count(labels, :neutral),
      negative_count: label_count(labels, :negative),
      skipped_count: length(Keyword.get(opts, :skipped, [])),
      conflict_count: length(Keyword.get(opts, :conflicts, [])),
      score_formula: Keyword.get(opts, :score_formula, "v1"),
      score_formula_version: 1,
      margin_mode: opts |> Keyword.get(:margin_mode, :profile_floor) |> to_string(),
      content_mode: opts |> Keyword.get(:content, :hash) |> to_string(),
      redaction_mode: "allowlist",
      provenance_summary: %{
        "source_trace_count" => length(source_paths),
        "deduplicated" => true
      },
      artifact_refs: collect_values(maps, [:route, "artifact_ref"]),
      runtime_profiles: collect_values(maps, [:route, "runtime_profile"]),
      route_hashes_digest: digest(Enum.sort(route_hashes) |> Enum.join("\n")),
      dataset_digest: digest(dataset_bytes)
    )
  end

  defp maybe_write(_path, _bytes, true), do: :ok
  defp maybe_write(nil, _bytes, false), do: {:error, :output_path_required}

  defp maybe_write(path, bytes, false) when is_binary(path) do
    File.mkdir_p!(Path.dirname(path))
    File.write(path, bytes)
  end

  defp maybe_write_report(opts, dry_run?) do
    report_out = Keyword.get(opts, :report_out)
    skipped = Keyword.get(opts, :skipped, [])
    conflicts = Keyword.get(opts, :conflicts, [])

    cond do
      dry_run? or is_nil(report_out) ->
        :ok

      skipped == [] and conflicts == [] ->
        :ok

      true ->
        maybe_write(
          report_out,
          canonical_json(%{skipped: skipped, conflicts: conflicts}) <> "\n",
          false
        )
    end
  end

  defp manifest_path(opts) do
    Keyword.get(opts, :manifest_out) ||
      case Keyword.get(opts, :out) do
        path when is_binary(path) -> Path.join(Path.dirname(path), "manifest.json")
        _other -> nil
      end
  end

  defp example_map(%FitnessExample{} = example), do: FitnessExample.to_map(example)
  defp example_map(example) when is_map(example), do: example

  defp label_count(labels, label),
    do: Map.get(labels, label, 0) + Map.get(labels, Atom.to_string(label), 0)

  defp collect_values(maps, path) do
    maps
    |> Enum.map(&get_in(&1, path))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @spec canonical_json(term()) :: String.t()
  def canonical_json(value) when is_map(value) do
    body =
      value
      |> Enum.map(fn {key, nested} -> {to_string(key), nested} end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join(",", fn {key, nested} ->
        Jason.encode!(key) <> ":" <> canonical_json(nested)
      end)

    "{" <> body <> "}"
  end

  def canonical_json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"

  def canonical_json(value) when is_boolean(value), do: Jason.encode!(value)

  def canonical_json(value) when is_atom(value) and not is_nil(value),
    do: Jason.encode!(Atom.to_string(value))

  def canonical_json(value), do: Jason.encode!(value)

  defp digest(bytes) do
    "sha256:" <>
      (bytes
       |> then(&:crypto.hash(:sha256, &1))
       |> Base.encode16(case: :lower))
  end
end
