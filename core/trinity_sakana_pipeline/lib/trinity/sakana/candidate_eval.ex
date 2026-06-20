defmodule Trinity.Sakana.CandidateEval do
  @moduledoc """
  Non-mutating candidate router proposal reports.

  Candidate evaluation compares exported fitness examples against either a
  candidate route JSON document or a candidate SafeTensors router vector
  preflight. It never writes accepted artifact paths or mutates model weights.
  """

  alias CrucibleFactorization.RouterVector
  alias CrucibleSafetensors.VectorInspect
  alias Trinity.Sakana.{AdaptationProposal, FitnessDatasetInspector, FitnessDatasetReader}

  @canonical_scale_count 9_216
  @canonical_hidden_size 1_024
  @canonical_output_count 10

  @spec evaluate(keyword()) :: {:ok, map()} | {:error, term()}
  def evaluate(opts) when is_list(opts) do
    fitness_path = Keyword.get(opts, :fitness)

    with {:ok, read_result} <- FitnessDatasetReader.read(fitness_path),
         {:ok, dataset_report} <-
           FitnessDatasetInspector.inspect(fitness_path, manifest: Keyword.get(opts, :manifest)) do
      examples = Enum.map(read_result.records, & &1.record)
      route_result = maybe_candidate_routes(opts, examples)
      vector_result = maybe_candidate_vector(opts)

      with {:ok, route_report} <- route_result,
           {:ok, vector_report} <- vector_result do
        proposal = build_proposal(examples, dataset_report, route_report, vector_report)
        {:ok, proposal}
      end
    end
  end

  def evaluate(_opts), do: {:error, :invalid_candidate_eval_options}

  defp maybe_candidate_routes(opts, examples) do
    case Keyword.get(opts, :candidate_routes) do
      nil ->
        {:ok, %{candidate_digest: nil, route_deltas: [], regressions: [], candidate_summary: %{}}}

      path when is_binary(path) ->
        with {:ok, candidate} <- read_candidate_routes(path) do
          {:ok, compare_candidate_routes(examples, candidate)}
        end
    end
  end

  defp read_candidate_routes(path) do
    if File.regular?(path) do
      case Jason.decode(File.read!(path)) do
        {:ok, %{"routes" => routes} = candidate} when is_list(routes) -> {:ok, candidate}
        {:ok, _other} -> {:error, {:invalid_candidate_routes, path}}
        {:error, error} -> {:error, {:invalid_candidate_routes, path, Exception.message(error)}}
      end
    else
      {:error, {:candidate_routes_not_found, path}}
    end
  end

  defp compare_candidate_routes(examples, candidate) do
    candidate_by_example = Map.new(candidate["routes"], &{&1["example_id"], &1})

    {deltas, regressions} =
      Enum.reduce(examples, {[], []}, fn example, {deltas, regressions} ->
        candidate_route = Map.get(candidate_by_example, example["example_id"])
        delta = route_delta(example, candidate_route)
        regression = regression(example, delta)
        {[delta | deltas], maybe_cons(regression, regressions)}
      end)

    %{
      candidate_digest: candidate["candidate_digest"] || digest(candidate),
      route_deltas: Enum.reverse(deltas),
      regressions: Enum.reverse(regressions),
      candidate_summary: %{
        "candidate_id" => candidate["candidate_id"],
        "route_count" => length(candidate["routes"])
      }
    }
  end

  defp route_delta(example, nil) do
    %{
      "example_id" => example["example_id"],
      "route_hash" => get_in(example, ["route", "route_hash"]),
      "status" => "missing_candidate_route",
      "changed_fields" => ["selected_agent_id", "selected_role_id"],
      "baseline" => baseline_route(example),
      "candidate" => nil
    }
  end

  defp route_delta(example, candidate_route) do
    baseline = baseline_route(example)
    candidate = Map.take(candidate_route, Map.keys(baseline))

    changed =
      baseline
      |> Enum.filter(fn {key, value} -> Map.get(candidate, key) != value end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    %{
      "example_id" => example["example_id"],
      "route_hash" => get_in(example, ["route", "route_hash"]),
      "status" => if(changed == [], do: "same", else: "changed"),
      "changed_fields" => changed,
      "baseline" => baseline,
      "candidate" => candidate
    }
  end

  defp baseline_route(example) do
    route = Map.get(example, "route", %{})

    %{
      "selected_agent_id" => route["selected_agent_id"],
      "selected_role_id" => route["selected_role_id"],
      "agent_margin" => route["agent_margin"],
      "role_margin" => route["role_margin"],
      "runtime_profile" => route["runtime_profile"]
    }
  end

  defp regression(_example, %{"status" => "same"}), do: nil

  defp regression(example, delta) do
    if get_in(example, ["fitness", "label"]) == "positive" and
         route_identity_changed?(delta["changed_fields"]) do
      %{
        "example_id" => example["example_id"],
        "route_hash" => get_in(example, ["route", "route_hash"]),
        "reason" => "positive_route_identity_changed",
        "changed_fields" => delta["changed_fields"]
      }
    end
  end

  defp route_identity_changed?(fields),
    do: "selected_agent_id" in fields or "selected_role_id" in fields

  defp maybe_candidate_vector(opts) do
    case Keyword.get(opts, :candidate_vector) do
      nil ->
        {:ok, nil}

      path when is_binary(path) ->
        key = Keyword.get(opts, :candidate_vector_key, "router_vector")
        scale_count = Keyword.get(opts, :candidate_scale_count, @canonical_scale_count)
        hidden_size = Keyword.get(opts, :candidate_hidden_size, @canonical_hidden_size)
        output_count = Keyword.get(opts, :candidate_output_count, @canonical_output_count)
        expected_count = scale_count + hidden_size * output_count

        with {:ok, inspect_report} <-
               VectorInspect.inspect(path,
                 tensor_key: key,
                 expected_count: expected_count
               ),
             {:ok, split_report} <-
               RouterVector.preflight(
                 %{"element_count" => inspect_report.element_count || 0},
                 scale_count,
                 hidden_size,
                 output_count
               ) do
          {:ok,
           %{
             "safetensors" => public_report(inspect_report, drop: [:path]),
             "split" => public_report(split_report),
             "valid" => inspect_report.valid? and split_report.valid?
           }}
        end
    end
  end

  defp build_proposal(examples, dataset_report, route_report, vector_report) do
    dataset_digest = dataset_report.digest

    candidate_digest =
      route_report.candidate_digest ||
        get_in(vector_report || %{}, ["safetensors", "file_sha256"])

    regressions = route_report.regressions
    verdict = verdict(dataset_report, regressions, vector_report, route_report)

    proposal =
      AdaptationProposal.new!(
        proposal_id: proposal_id(dataset_digest, candidate_digest, route_report, vector_report),
        dataset_digest: dataset_digest,
        candidate_digest: candidate_digest,
        baseline_summary: %{
          "record_count" => length(examples),
          "positive_count" => dataset_report.positive_count,
          "neutral_count" => dataset_report.neutral_count,
          "negative_count" => dataset_report.negative_count
        },
        candidate_summary: route_report.candidate_summary,
        route_deltas: route_report.route_deltas,
        score_delta_summary: %{"score_formula" => "v1", "candidate_scoring" => "not_run"},
        regressions: regressions,
        vector_preflight: vector_report,
        verdict: elem(verdict, 0),
        status_reason: elem(verdict, 1)
      )

    AdaptationProposal.to_map(proposal)
  end

  defp verdict(%{dataset_status: status}, _regressions, _vector, _routes)
       when status != "candidate_eval_ready",
       do: {"needs_more_evidence", status}

  defp verdict(_dataset, regressions, _vector, _routes) when regressions != [],
    do: {"reject", "positive_route_regression"}

  defp verdict(_dataset, _regressions, %{"valid" => true}, _routes),
    do: {"artifact_gate_ready", nil}

  defp verdict(_dataset, _regressions, _vector, %{route_deltas: deltas}) when deltas != [],
    do: {"shadow_ready", nil}

  defp verdict(_dataset, _regressions, _vector, _routes),
    do: {"needs_more_evidence", "no_candidate_input"}

  defp proposal_id(dataset_digest, candidate_digest, route_report, vector_report) do
    "proposal:" <>
      digest(%{
        dataset_digest: dataset_digest,
        candidate_digest: candidate_digest,
        routes: route_report,
        vector: vector_report
      })
  end

  defp maybe_cons(nil, list), do: list
  defp maybe_cons(value, list), do: [value | list]

  defp public_report(report, opts \\ []) do
    drop = Keyword.get(opts, :drop, [])

    report
    |> Map.drop(drop)
    |> stringify()
  end

  defp stringify(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), stringify(value)} end)

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(nil), do: nil
  defp stringify(value) when is_boolean(value), do: value
  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value), do: value

  defp digest(value) do
    value
    |> normalize()
    |> :erlang.term_to_binary([:compressed])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> then(&("sha256:" <> &1))
  end

  defp normalize(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested} -> {to_string(key), normalize(nested)} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp normalize(value) when is_list(value), do: Enum.map(value, &normalize/1)
  defp normalize(value), do: value
end
