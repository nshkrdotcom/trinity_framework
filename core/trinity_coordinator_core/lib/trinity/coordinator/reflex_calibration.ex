defmodule Trinity.Coordinator.ReflexCalibration do
  @moduledoc """
  Deterministic threshold sweep for TRINITY router reflex policy.

  The module accepts exported fitness examples as string-key maps. It does not
  mutate `ReflexPolicy` defaults; it only reports candidate threshold economics.
  """

  alias Trinity.Sakana.{MarginDefaults, ReflexCalibrationReport}

  @default_high_multipliers [2.0, 4.0, 8.0]
  @default_low_multipliers [0.5, 1.0]

  @spec calibrate([map()], keyword()) :: {:ok, map()} | {:error, term()}
  def calibrate(examples, opts \\ [])

  def calibrate(examples, opts) when is_list(examples) and is_list(opts) do
    margin_mode = normalize_margin_mode(Keyword.get(opts, :margin_mode, :profile_floor))

    high_multipliers =
      normalize_multipliers(Keyword.get(opts, :high_multipliers, @default_high_multipliers))

    low_multipliers =
      normalize_multipliers(Keyword.get(opts, :low_multipliers, @default_low_multipliers))

    candidates =
      for high <- high_multipliers,
          low <- low_multipliers do
        evaluate_candidate(examples, margin_mode, high, low)
      end
      |> Enum.sort_by(&{-&1["score"], &1["high_multiplier"], &1["low_multiplier"]})

    recommended = List.first(candidates)
    status = if examples != [] and candidates != [], do: "ok", else: "insufficient_evidence"

    report =
      ReflexCalibrationReport.new!(
        fitness_path: Keyword.get(opts, :fitness_path),
        record_count: length(examples),
        margin_mode: Atom.to_string(margin_mode),
        candidate_count: length(candidates),
        recommended_thresholds: recommended_thresholds(recommended),
        recommended_score: if(recommended, do: recommended["score"], else: nil),
        status: status,
        status_reason: if(status == "ok", do: nil, else: "no_examples_or_candidates"),
        candidates: candidates
      )

    {:ok, ReflexCalibrationReport.to_map(report)}
  end

  def calibrate(_examples, _opts), do: {:error, :invalid_calibration_examples}

  defp evaluate_candidate(examples, margin_mode, high_multiplier, low_multiplier) do
    classified =
      Enum.map(examples, &classify_example(&1, margin_mode, high_multiplier, low_multiplier))

    accepted_direct = Enum.count(classified, &(&1.class == "high" and &1.outcome == "accepted"))

    high_bad =
      Enum.count(
        classified,
        &(&1.class == "high" and &1.outcome in ["rejected", "failed", "revise", "revised"])
      )

    low_accepted = Enum.count(classified, &(&1.class == "low" and &1.outcome == "accepted"))
    insufficient = Enum.count(classified, &(&1.class == "missing"))

    score =
      accepted_direct * 1.0 - high_bad * 2.0 - low_accepted * 0.25 - insufficient * 0.5

    %{
      "high_multiplier" => high_multiplier,
      "low_multiplier" => low_multiplier,
      "score" => score,
      "accepted_direct_count" => accepted_direct,
      "high_bad_count" => high_bad,
      "low_accepted_count" => low_accepted,
      "insufficient_margin_count" => insufficient,
      "class_counts" => Enum.frequencies_by(classified, & &1.class)
    }
  end

  defp classify_example(example, margin_mode, high_multiplier, low_multiplier) do
    route = Map.get(example, "route", %{})
    runtime_profile = Map.get(route, "runtime_profile", "mock_tiny")
    floors = MarginDefaults.defaults(runtime_profile)
    agent_margin = Map.get(route, "agent_margin")
    role_margin = Map.get(route, "role_margin")

    class =
      classify_margins(
        margin_mode,
        agent_margin,
        role_margin,
        floors,
        high_multiplier,
        low_multiplier
      )

    %{
      class: class,
      outcome: Map.get(Map.get(example, "outcome", %{}), "verifier_status", "unknown")
    }
  end

  defp recommended_thresholds(nil), do: nil

  defp recommended_thresholds(candidate) do
    %{
      "high_multiplier" => candidate["high_multiplier"],
      "low_multiplier" => candidate["low_multiplier"]
    }
  end

  defp classify_margins(_mode, agent_margin, role_margin, _floors, _high, _low)
       when not is_number(agent_margin) or not is_number(role_margin),
       do: "missing"

  defp classify_margins(:absolute, agent_margin, role_margin, _floors, high, low) do
    margin_class(agent_margin, role_margin, high, high, low, low)
  end

  defp classify_margins(:profile_floor, agent_margin, role_margin, floors, high, low) do
    margin_class(
      agent_margin,
      role_margin,
      floors.agent * high,
      floors.role * high,
      floors.agent * low,
      floors.role * low
    )
  end

  defp margin_class(agent_margin, role_margin, high_agent, high_role, low_agent, low_role) do
    cond do
      agent_margin < low_agent or role_margin < low_role -> "low"
      agent_margin >= high_agent and role_margin >= high_role -> "high"
      true -> "medium"
    end
  end

  defp normalize_margin_mode(:profile_floor), do: :profile_floor
  defp normalize_margin_mode("profile_floor"), do: :profile_floor
  defp normalize_margin_mode(:absolute), do: :absolute
  defp normalize_margin_mode("absolute"), do: :absolute

  defp normalize_margin_mode(other),
    do: raise(ArgumentError, "invalid margin mode: #{inspect(other)}")

  defp normalize_multipliers(values) when is_list(values) do
    values
    |> Enum.filter(&(is_number(&1) and &1 > 0))
    |> Enum.map(&(&1 * 1.0))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_multipliers(_values), do: []
end
