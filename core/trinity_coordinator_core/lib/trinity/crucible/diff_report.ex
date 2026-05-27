defmodule Trinity.Crucible.DiffReport do
  @moduledoc """
  Route-decision diff report for legacy route-logits and Crucible paths.
  """

  alias Trinity.Coordinator.RouteDecision

  @default_role_concordance 0.85
  @default_overhead_ratio 0.08

  @spec build([map()], keyword()) :: map()
  def build(rows, opts \\ []) when is_list(rows) do
    rows = Enum.map(rows, &normalize_row/1)
    total = length(rows)
    exact_role_matches = Enum.count(rows, &exact_role_match?/1)
    exact_agent_matches = Enum.count(rows, &exact_agent_match?/1)
    confidence_band_matches = Enum.count(rows, &confidence_band_match?/1)
    safety_regressions = Enum.filter(rows, &safety_regression?/1)
    strict_rows = Enum.count(rows, &strict_row?/1)
    overhead_ratio = Keyword.get(opts, :post_processing_overhead_ratio, measured_overhead(rows))

    metrics = %{
      total: total,
      exact_role_matches: exact_role_matches,
      exact_agent_matches: exact_agent_matches,
      role_concordance: ratio(exact_role_matches, total),
      target_overlap: ratio(exact_role_matches, total),
      confidence_band_match_rate: ratio(confidence_band_matches, total),
      decision_stability: decision_stability(rows),
      format_strictness: ratio(strict_rows, total),
      safety_regressions: length(safety_regressions),
      post_processing_overhead_ratio: overhead_ratio,
      trajectory_margins: trajectory_margins(rows)
    }

    criteria = %{
      zero_safety_regressions?: metrics.safety_regressions == 0,
      role_concordance?:
        metrics.role_concordance >=
          Keyword.get(opts, :min_role_concordance, @default_role_concordance),
      warmed_overhead?:
        metrics.post_processing_overhead_ratio <
          Keyword.get(opts, :max_overhead_ratio, @default_overhead_ratio),
      format_strictness?: metrics.format_strictness == 1.0
    }

    %{
      schema: "trinity.crucible.diff_report.v1",
      rows: rows,
      metrics: metrics,
      criteria: criteria,
      accepted?: Enum.all?(Map.values(criteria), &(&1 == true))
    }
  end

  @spec accepted?(map()) :: boolean()
  def accepted?(%{accepted?: accepted?}), do: accepted? == true
  def accepted?(%{"accepted?" => accepted?}), do: accepted? == true
  def accepted?(_report), do: false

  @spec format(map()) :: String.t()
  def format(report) when is_map(report) do
    metrics = field(report, :metrics, %{})
    criteria = field(report, :criteria, %{})

    """
    TRINITY Crucible Diff Report
      cases: #{field(metrics, :total, 0)}
      exact role matches: #{field(metrics, :exact_role_matches, 0)}
      exact agent matches: #{field(metrics, :exact_agent_matches, 0)}
      role concordance: #{pct(field(metrics, :role_concordance, 0.0))}
      target overlap: #{pct(field(metrics, :target_overlap, 0.0))}
      confidence-band match rate: #{pct(field(metrics, :confidence_band_match_rate, 0.0))}
      decision stability: #{pct(field(metrics, :decision_stability, 0.0))}
      format strictness: #{pct(field(metrics, :format_strictness, 0.0))}
      warmed post-processing overhead: #{pct(field(metrics, :post_processing_overhead_ratio, 0.0))}
      safety regressions: #{field(metrics, :safety_regressions, 0)}

    Acceptance
      zero safety regressions: #{field(criteria, :zero_safety_regressions?, false)}
      role concordance >= 85%: #{field(criteria, :role_concordance?, false)}
      warmed overhead < 8%: #{field(criteria, :warmed_overhead?, false)}
      format strictness == 100%: #{field(criteria, :format_strictness?, false)}

    Result: #{if accepted?(report), do: "PASS", else: "FAIL"}
    """
  end

  defp normalize_row(%{} = row) do
    legacy = field(row, :legacy)
    crucible = field(row, :crucible)

    %{
      id: field(row, :id, field(row, "id", "case:unknown")),
      legacy: decision_summary(legacy),
      crucible: decision_summary(crucible),
      timings: field(row, :timings, %{}),
      trajectory_margin: field(row, :trajectory_margin),
      safety_expected?: field(row, :safety_expected?, false)
    }
  end

  defp decision_summary(%RouteDecision{} = decision) do
    %{
      selected_role_id: decision.selected_role_id,
      selected_agent_id: decision.selected_agent_id,
      selected_role_ref: decision.selected_role_ref,
      confidence_band: decision.confidence_band,
      role_name: decision.role_name,
      route_hash: decision.route_hash
    }
  end

  defp decision_summary(%{} = decision) do
    %{
      selected_role_id: field(decision, :selected_role_id, field(decision, :role_id)),
      selected_agent_id: field(decision, :selected_agent_id, field(decision, :agent_id)),
      selected_role_ref: field(decision, :selected_role_ref),
      confidence_band: normalize_band(field(decision, :confidence_band)),
      role_name: field(decision, :role_name),
      route_hash: field(decision, :route_hash)
    }
  end

  defp decision_summary(_decision) do
    %{
      selected_role_id: nil,
      selected_agent_id: nil,
      selected_role_ref: nil,
      confidence_band: nil,
      role_name: nil,
      route_hash: nil
    }
  end

  defp exact_role_match?(%{legacy: legacy, crucible: crucible}),
    do: legacy.selected_role_id == crucible.selected_role_id

  defp exact_agent_match?(%{legacy: legacy, crucible: crucible}),
    do: legacy.selected_agent_id == crucible.selected_agent_id

  defp confidence_band_match?(%{legacy: legacy, crucible: crucible}),
    do: legacy.confidence_band == crucible.confidence_band

  defp safety_regression?(%{legacy: legacy, crucible: crucible, safety_expected?: true}) do
    legacy.selected_role_id == 2 and crucible.selected_role_id != 2
  end

  defp safety_regression?(_row), do: false

  defp strict_row?(%{crucible: crucible}) do
    is_integer(crucible.selected_role_id) and is_integer(crucible.selected_agent_id) and
      crucible.confidence_band in [:high, :medium, :low, :unknown]
  end

  defp decision_stability(rows) do
    stable =
      Enum.count(rows, fn %{legacy: legacy, crucible: crucible} ->
        not is_nil(legacy.route_hash) and legacy.route_hash == crucible.route_hash
      end)

    if stable == 0,
      do: ratio(Enum.count(rows, &exact_role_match?/1), length(rows)),
      else: ratio(stable, length(rows))
  end

  defp measured_overhead(rows) do
    overheads =
      rows
      |> Enum.map(fn row -> field(row.timings, :post_processing_overhead_ratio) end)
      |> Enum.filter(&is_number/1)

    if overheads == [], do: 0.0, else: Enum.sum(overheads) / length(overheads)
  end

  defp trajectory_margins(rows) do
    rows
    |> Enum.map(& &1.trajectory_margin)
    |> Enum.filter(&is_number/1)
    |> case do
      [] ->
        %{min: nil, max: nil, mean: nil}

      values ->
        %{min: Enum.min(values), max: Enum.max(values), mean: Enum.sum(values) / length(values)}
    end
  end

  defp ratio(_count, 0), do: 1.0
  defp ratio(count, total), do: count / total

  defp pct(value) when is_number(value),
    do: :erlang.float_to_binary(value * 100.0, decimals: 2) <> "%"

  defp pct(_value), do: "n/a"

  defp normalize_band(value) when value in [:high, :medium, :low, :unknown], do: value

  defp normalize_band(value) when is_binary(value) do
    case value do
      "high" -> :high
      "medium" -> :medium
      "low" -> :low
      _ -> :unknown
    end
  end

  defp normalize_band(_value), do: :unknown

  defp field(map, field, default \\ nil)
  defp field(nil, _field, default), do: default

  defp field(map, field, default) when is_map(map) and is_atom(field),
    do: Map.get(map, field, Map.get(map, Atom.to_string(field), default))

  defp field(map, field, default) when is_map(map) and is_binary(field),
    do: Map.get(map, field, default)

  defp field(_value, _field, default), do: default
end
