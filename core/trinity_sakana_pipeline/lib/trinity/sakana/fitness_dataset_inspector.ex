defmodule Trinity.Sakana.FitnessDatasetInspector do
  @moduledoc "Builds deterministic health reports for Sakana fitness datasets."

  alias CrucibleSignalTrace.{DatasetDigest, SecretScan}
  alias Trinity.Sakana.{FitnessDatasetReader, FitnessDatasetReport}

  @spec inspect(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def inspect(fitness_path, opts \\ []) when is_binary(fitness_path) and is_list(opts) do
    manifest_path = Keyword.get(opts, :manifest)

    with {:ok, read_result} <-
           FitnessDatasetReader.read(fitness_path,
             skip_invalid: Keyword.get(opts, :skip_invalid, false)
           ),
         {:ok, manifest} <- FitnessDatasetReader.read_manifest(manifest_path),
         {:ok, digest_report} <-
           DatasetDigest.digest_rows(Enum.map(read_result.records, & &1.record)) do
      rows = Enum.map(read_result.records, & &1.record)
      labels = Enum.frequencies_by(rows, &field(&1, ["fitness", "label"], "unknown"))
      secret_scan = SecretScan.scan(rows)
      manifest_digest_verified = manifest_digest_verified?(manifest, digest_report.dataset_digest)
      status = dataset_status(rows, secret_scan, manifest, manifest_digest_verified)

      report =
        FitnessDatasetReport.new!(
          fitness_path: fitness_path,
          manifest_path: manifest_path,
          record_count: length(rows),
          positive_count: Map.get(labels, "positive", 0),
          neutral_count: Map.get(labels, "neutral", 0),
          negative_count: Map.get(labels, "negative", 0),
          source_counts: count_by(rows, ["source", "kind"]),
          runtime_profiles: count_by(rows, ["route", "runtime_profile"]),
          artifact_refs: count_by(rows, ["route", "artifact_ref"]),
          route_path_counts: count_by(rows, ["route", "route_path"]),
          reflex_counts: count_by(rows, ["route", "reflex", "action"]),
          missing_outcome_counts: missing_outcome_counts(rows),
          secret_scan: secret_scan_map(secret_scan),
          digest: digest_report.dataset_digest,
          manifest_digest_verified: manifest_digest_verified,
          dataset_status: elem(status, 0),
          status_reason: elem(status, 1)
        )

      {:ok, FitnessDatasetReport.to_map(report)}
    end
  end

  defp manifest_digest_verified?(nil, _digest), do: false

  defp manifest_digest_verified?(manifest, digest),
    do: Map.get(manifest, "dataset_digest") == digest

  defp dataset_status(_rows, %{ok?: false}, _manifest, _verified?),
    do: {"invalid", "secret_scan_failed"}

  defp dataset_status(_rows, _scan, manifest, false) when is_map(manifest),
    do: {"invalid", "manifest_digest_mismatch"}

  defp dataset_status([], _scan, _manifest, _verified?), do: {"invalid", "empty_dataset"}

  defp dataset_status(rows, _scan, nil, _verified?) when rows != [],
    do: {"replay_ready", "manifest_missing"}

  defp dataset_status(rows, _scan, _manifest, true) do
    labels = Enum.frequencies_by(rows, &field(&1, ["fitness", "label"], "unknown"))

    if Map.get(labels, "positive", 0) > 0 do
      {"candidate_eval_ready", nil}
    else
      {"calibration_only", "no_positive_examples"}
    end
  end

  defp count_by(rows, path) do
    rows
    |> Enum.map(&field(&1, path))
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
    |> Enum.into(%{}, fn {key, count} -> {to_string(key), count} end)
  end

  defp missing_outcome_counts(rows) do
    rows
    |> Enum.filter(&(field(&1, ["outcome", "verifier_status"], "unknown") == "unknown"))
    |> Enum.frequencies_by(&field(&1, ["source", "kind"], "unknown"))
  end

  defp secret_scan_map(scan) do
    %{
      "ok" => scan.ok?,
      "findings" =>
        Enum.map(scan.findings, fn finding ->
          %{
            "path" => Enum.join(finding.path, "."),
            "location" => finding.location,
            "term" => finding.term
          }
        end)
    }
  end

  defp field(map, path, default \\ nil)
  defp field(map, [], _default), do: map

  defp field(map, [key | rest], default) when is_map(map),
    do: map |> Map.get(key) |> field(rest, default)

  defp field(_map, _path, default), do: default
end
