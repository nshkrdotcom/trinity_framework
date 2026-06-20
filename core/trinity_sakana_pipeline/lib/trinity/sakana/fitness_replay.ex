defmodule Trinity.Sakana.FitnessReplay do
  @moduledoc "Replays score-v1 over exported Sakana fitness examples."

  alias CrucibleSignalTrace.DatasetDigest
  alias Trinity.Sakana.{FitnessDatasetReader, FitnessReplayReport, FitnessScore}

  @spec replay(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def replay(fitness_path, opts \\ []) when is_binary(fitness_path) and is_list(opts) do
    manifest_path = Keyword.get(opts, :manifest)

    with {:ok, read_result} <-
           FitnessDatasetReader.read(fitness_path,
             skip_invalid: Keyword.get(opts, :skip_invalid, false)
           ),
         {:ok, manifest} <- FitnessDatasetReader.read_manifest(manifest_path),
         {:ok, digest_report} <-
           DatasetDigest.digest_rows(Enum.map(read_result.records, & &1.record)) do
      rows = Enum.map(read_result.records, & &1.record)
      mismatches = Enum.flat_map(rows, &mismatches(&1, opts))

      report =
        FitnessReplayReport.new!(
          fitness_path: fitness_path,
          manifest_path: manifest_path,
          record_count: length(rows),
          score_mismatch_count: Enum.count(mismatches, &(&1["kind"] == "score")),
          label_mismatch_count: Enum.count(mismatches, &(&1["kind"] == "label")),
          mismatches: mismatches,
          component_summary: component_summary(rows, opts),
          group_summary: group_summary(rows),
          reflex_economics: reflex_economics(rows),
          dataset_digest: digest_report.dataset_digest,
          status: if(mismatches == [], do: "ok", else: "mismatch"),
          status_reason: manifest_status(manifest, digest_report.dataset_digest)
        )

      {:ok, FitnessReplayReport.to_map(report)}
    end
  end

  defp mismatches(example, opts) do
    score = recompute(example, opts)
    stored = field(example, ["fitness"], %{})
    stored_score = field(stored, ["score"])
    stored_label = field(stored, ["label"])

    []
    |> maybe_score_mismatch(example, stored_score, score.score)
    |> maybe_label_mismatch(example, stored_label, Atom.to_string(score.label))
  end

  defp maybe_score_mismatch(acc, example, stored, actual) when is_number(stored) do
    if abs(stored - actual) > 1.0e-9,
      do: [
        %{
          "kind" => "score",
          "example_id" => example["example_id"],
          "stored" => stored,
          "actual" => actual
        }
        | acc
      ],
      else: acc
  end

  defp maybe_score_mismatch(acc, example, stored, actual),
    do: [
      %{
        "kind" => "score",
        "example_id" => example["example_id"],
        "stored" => stored,
        "actual" => actual
      }
      | acc
    ]

  defp maybe_label_mismatch(acc, example, stored, actual) do
    if stored == actual,
      do: acc,
      else: [
        %{
          "kind" => "label",
          "example_id" => example["example_id"],
          "stored" => stored,
          "actual" => actual
        }
        | acc
      ]
  end

  defp recompute(example, opts) do
    route = field(example, ["route"], %{})
    outcome = field(example, ["outcome"], %{})

    FitnessScore.score_v1(
      %{
        verifier_status: outcome["verifier_status"],
        agent_margin: route["agent_margin"],
        role_margin: route["role_margin"],
        revision_count: outcome["revision_count"],
        runtime_profile: route["runtime_profile"],
        observed_latency_ms: outcome["observed_latency_ms"],
        estimated_cost_usd: outcome["estimated_cost_usd"],
        budget_exceeded: outcome["budget_exceeded"]
      },
      score_opts(opts)
    )
  end

  defp component_summary(rows, opts) do
    rows
    |> Enum.map(&recompute(&1, opts).components)
    |> Enum.reduce(%{}, &add_components/2)
    |> finalize_summary()
  end

  defp add_components(components, acc), do: Enum.reduce(components, acc, &add_component/2)

  defp add_component({key, value}, acc) when is_number(value),
    do: add_number(acc, to_string(key), value)

  defp add_component(_component, acc), do: acc

  defp group_summary(rows) do
    %{
      "selected_role_id" => count_by(rows, ["route", "selected_role_id"]),
      "selected_agent_id" => count_by(rows, ["route", "selected_agent_id"]),
      "runtime_profile" => count_by(rows, ["route", "runtime_profile"]),
      "source_kind" => count_by(rows, ["source", "kind"]),
      "confidence_band" => count_by(rows, ["route", "confidence_band"]),
      "reflex_action" => count_by(rows, ["route", "reflex", "action"])
    }
  end

  defp reflex_economics(rows) do
    rows
    |> Enum.group_by(&field(&1, ["route", "reflex", "action"], "none"))
    |> Map.new(fn {action, examples} -> {to_string(action), economics(examples)} end)
  end

  defp economics(rows) do
    count = length(rows)

    %{
      "count" => count,
      "acceptance_rate" => rate(rows, &accepted?/1),
      "revision_rate" => rate(rows, &(number(field(&1, ["outcome", "revision_count"], 0)) > 0)),
      "rejection_failure_rate" => rate(rows, &rejected_or_failed?/1),
      "avg_latency_ms" => average(rows, ["outcome", "observed_latency_ms"]),
      "avg_cost_usd" => average(rows, ["outcome", "estimated_cost_usd"]),
      "budget_exceeded_rate" =>
        rate(rows, &truthy?(field(&1, ["outcome", "budget_exceeded"], false)))
    }
  end

  defp manifest_status(nil, _digest), do: "manifest_missing"

  defp manifest_status(manifest, digest) do
    if Map.get(manifest, "dataset_digest") == digest, do: nil, else: "manifest_digest_mismatch"
  end

  defp score_opts(opts) do
    [
      margin_mode: Keyword.get(opts, :margin_mode, :profile_floor),
      margin_scale: Keyword.get(opts, :margin_scale, 1.0),
      latency_target_ms: Keyword.get(opts, :latency_target_ms),
      cost_target_usd: Keyword.get(opts, :cost_target_usd),
      positive_threshold: Keyword.get(opts, :positive_threshold, 0.67),
      negative_threshold: Keyword.get(opts, :negative_threshold, 0.33)
    ]
  end

  defp count_by(rows, path),
    do: rows |> Enum.map(&field(&1, path)) |> Enum.reject(&is_nil/1) |> Enum.frequencies()

  defp accepted?(example), do: field(example, ["outcome", "verifier_status"]) == "accepted"

  defp rejected_or_failed?(example),
    do: field(example, ["outcome", "verifier_status"]) in ["rejected", "failed"]

  defp rate([], _fun), do: 0.0
  defp rate(rows, fun), do: Enum.count(rows, fun) / length(rows)

  defp average(rows, path) do
    values = rows |> Enum.map(&field(&1, path)) |> Enum.filter(&is_number/1)
    if values == [], do: nil, else: Enum.sum(values) / length(values)
  end

  defp add_number(acc, key, value) do
    current = Map.get(acc, key, %{count: 0, sum: 0.0, min: value, max: value})

    Map.put(acc, key, %{
      count: current.count + 1,
      sum: current.sum + value,
      min: min(current.min, value),
      max: max(current.max, value)
    })
  end

  defp finalize_summary(summary) do
    Map.new(summary, fn {key, stats} ->
      {key,
       %{
         "count" => stats.count,
         "min" => stats.min,
         "max" => stats.max,
         "mean" => stats.sum / stats.count
       }}
    end)
  end

  defp truthy?(true), do: true
  defp truthy?(_value), do: false
  defp number(value) when is_number(value), do: value
  defp number(_value), do: 0

  defp field(map, path, default \\ nil)
  defp field(map, [], _default), do: map

  defp field(map, [key | rest], default) when is_map(map),
    do: map |> Map.get(key) |> field(rest, default)

  defp field(_map, _path, default), do: default
end
