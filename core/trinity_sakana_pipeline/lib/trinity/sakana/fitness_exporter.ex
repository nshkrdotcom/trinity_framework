defmodule Trinity.Sakana.FitnessExporter do
  @moduledoc "Coordinates trace reading, fitness assembly, scoring, and writing."

  alias Trinity.Sakana.{
    FitnessExample,
    FitnessJsonlWriter,
    FitnessScore,
    TraceFitnessAssembler,
    TraceFitnessReader
  }

  @spec export([String.t()], keyword()) :: {:ok, map()} | {:error, term()}
  def export(trace_paths, opts \\ []) when is_list(trace_paths) and is_list(opts) do
    with :ok <- validate_formula(opts),
         {:ok, read_result} <-
           TraceFitnessReader.read(trace_paths,
             skip_invalid: Keyword.get(opts, :skip_invalid, false)
           ) do
      assembled =
        TraceFitnessAssembler.assemble(read_result.records,
          content: Keyword.get(opts, :content, :hash)
        )

      examples = Enum.map(assembled.examples, &score_example(&1, opts))

      writer_opts =
        opts
        |> Keyword.put(:source_trace_paths, trace_paths)
        |> Keyword.put(:skipped, read_result.skipped)
        |> Keyword.put(:conflicts, assembled.conflicts)

      with {:ok, write_result} <- FitnessJsonlWriter.write(examples, writer_opts) do
        {:ok, summary(write_result.manifest)}
      end
    end
  end

  defp score_example(candidate, opts) do
    route = candidate.route
    outcome = candidate.outcome

    score =
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

    FitnessExample.new!(
      example_id: candidate.example_id,
      source: candidate.source,
      input: candidate.input,
      route: candidate.route,
      outcome: candidate.outcome,
      fitness: %{
        "score" => score.score,
        "label" => Atom.to_string(score.label),
        "formula" => score.formula,
        "formula_version" => score.formula_version,
        "margin_mode" => Atom.to_string(score.margin_mode),
        "components" => stringify_keys(score.components)
      },
      provenance: candidate.provenance
    )
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

  defp validate_formula(opts) do
    case Keyword.get(opts, :score_formula, "v1") do
      value when value in ["v1", :v1] -> :ok
      other -> {:error, {:unsupported_score_formula, other}}
    end
  end

  defp summary(manifest) do
    manifest
    |> Map.from_struct()
    |> Map.take([
      :schema_version,
      :record_count,
      :positive_count,
      :neutral_count,
      :negative_count,
      :skipped_count,
      :conflict_count,
      :route_hashes_digest,
      :dataset_digest
    ])
    |> Map.put(:ok, true)
  end

  defp stringify_keys(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end
end
