defmodule Trinity.Sakana.FitnessScore do
  @moduledoc "Deterministic Sakana route fitness scoring."

  alias Trinity.Sakana.MarginDefaults

  @formula "v1"
  @formula_version 1
  @default_positive_threshold 0.67
  @default_negative_threshold 0.33

  @enforce_keys [:score, :label, :formula, :formula_version, :margin_mode, :components]
  defstruct [:score, :label, :formula, :formula_version, :margin_mode, :components]

  @type label :: :positive | :neutral | :negative
  @type t :: %__MODULE__{}

  @spec score_v1(map(), keyword()) :: t()
  def score_v1(attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    margin_mode = normalize_margin_mode(Keyword.get(opts, :margin_mode, :profile_floor))
    positive_threshold = Keyword.get(opts, :positive_threshold, @default_positive_threshold)
    negative_threshold = Keyword.get(opts, :negative_threshold, @default_negative_threshold)
    validate_thresholds!(positive_threshold, negative_threshold)

    components = %{
      base: 0.5,
      verifier: verifier_contribution(field(attrs, :verifier_status, :unknown)),
      margin:
        0.2 *
          margin_strength(
            attrs,
            margin_mode,
            Keyword.get(opts, :margin_scale, 1.0)
          ),
      margin_strength: margin_strength(attrs, margin_mode, Keyword.get(opts, :margin_scale, 1.0)),
      revision: -0.1 * min(non_negative_integer(field(attrs, :revision_count, 0)), 3),
      latency:
        target_contribution(
          field(attrs, :observed_latency_ms),
          Keyword.get(opts, :latency_target_ms)
        ),
      cost:
        target_contribution(
          field(attrs, :estimated_cost_usd),
          Keyword.get(opts, :cost_target_usd)
        ),
      budget: if(field(attrs, :budget_exceeded, false), do: -0.25, else: 0.0)
    }

    score =
      components
      |> Map.take([:base, :verifier, :margin, :revision, :latency, :cost, :budget])
      |> Map.values()
      |> Enum.sum()
      |> clamp(0.0, 1.0)

    %__MODULE__{
      score: score,
      label: label(score, positive_threshold, negative_threshold),
      formula: @formula,
      formula_version: @formula_version,
      margin_mode: margin_mode,
      components: components
    }
  end

  defp verifier_contribution(status) when status in [:accepted, "accepted", :ok, "ok"], do: 0.3

  defp verifier_contribution(status) when status in [:revise, "revise", :revised, "revised"],
    do: -0.2

  defp verifier_contribution(status)
       when status in [:rejected, "rejected", :failed, "failed"],
       do: -0.35

  defp verifier_contribution(_status), do: 0.0

  defp margin_strength(attrs, :profile_floor, _margin_scale) do
    floors = MarginDefaults.defaults(field(attrs, :runtime_profile))
    agent_ratio = safe_ratio(field(attrs, :agent_margin), floors.agent)
    role_ratio = safe_ratio(field(attrs, :role_margin), floors.role)
    min_ratio = min(agent_ratio, role_ratio)
    clamp(:math.log2(max(min_ratio, 1.0)) / 4.0, 0.0, 1.0)
  end

  defp margin_strength(attrs, :absolute, margin_scale)
       when is_number(margin_scale) and margin_scale > 0 do
    min_margin = min(number(field(attrs, :agent_margin)), number(field(attrs, :role_margin)))
    clamp(min_margin / margin_scale, 0.0, 1.0)
  end

  defp margin_strength(_attrs, :absolute, margin_scale) do
    raise ArgumentError, "margin_scale must be positive, got: #{inspect(margin_scale)}"
  end

  defp target_contribution(observed, target)
       when is_number(observed) and is_number(target) and target > 0 do
    0.05 * clamp(1.0 - observed / target, -1.0, 1.0)
  end

  defp target_contribution(_observed, _target), do: 0.0

  defp label(score, positive, _negative) when score >= positive, do: :positive
  defp label(score, _positive, negative) when score <= negative, do: :negative
  defp label(_score, _positive, _negative), do: :neutral

  defp normalize_margin_mode(:profile_floor), do: :profile_floor
  defp normalize_margin_mode("profile_floor"), do: :profile_floor
  defp normalize_margin_mode(:absolute), do: :absolute
  defp normalize_margin_mode("absolute"), do: :absolute

  defp normalize_margin_mode(other),
    do: raise(ArgumentError, "unsupported margin mode: #{inspect(other)}")

  defp validate_thresholds!(positive, negative)
       when is_number(positive) and is_number(negative) and negative <= positive,
       do: :ok

  defp validate_thresholds!(positive, negative) do
    raise ArgumentError,
          "invalid fitness thresholds: positive=#{inspect(positive)} negative=#{inspect(negative)}"
  end

  defp safe_ratio(value, floor) when is_number(value) and is_number(floor) and floor > 0,
    do: value / floor

  defp safe_ratio(_value, _floor), do: 0.0
  defp number(value) when is_number(value), do: value
  defp number(_value), do: 0.0
  defp non_negative_integer(value) when is_integer(value) and value >= 0, do: value
  defp non_negative_integer(_value), do: 0
  defp clamp(value, low, high), do: value |> max(low) |> min(high)

  defp field(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end
