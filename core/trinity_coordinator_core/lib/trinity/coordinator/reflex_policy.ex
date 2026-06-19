defmodule Trinity.Coordinator.ReflexPolicy do
  @moduledoc """
  Converts route confidence into a bounded coordinator execution action.

  Profile-floor mode derives low thresholds from
  `Trinity.Sakana.MarginDefaults` and high thresholds at four times each
  floor. Absolute mode defaults conservatively to low thresholds of `0.1` and
  high thresholds of `1.0`; callers should supply explicit thresholds when an
  absolute scale has a different meaning.

  The module accepts only fixed confidence/mode values and never creates atoms
  from input. Its result is an allowlisted explanation suitable for traces.
  """

  alias Trinity.Coordinator.RoleInjector
  alias Trinity.Sakana.MarginDefaults

  @absolute_thresholds %{
    high_agent: 1.0,
    high_role: 1.0,
    low_agent: 0.1,
    low_role: 0.1
  }
  @default_force_sequence [:thinker, :verifier]

  @type confidence_class :: :high | :medium | :low
  @type action :: :direct_dispatch | :normal_dispatch | :thinker_then_verifier

  @spec evaluate(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def evaluate(route_or_decision, opts \\ [])

  def evaluate(route_or_decision, opts) when is_map(route_or_decision) and is_list(opts) do
    with {:ok, config} <- config(route_or_decision, opts),
         {:ok, classification} <- classification(route_or_decision, config) do
      {:ok, explanation(route_or_decision, config, classification)}
    end
  end

  def evaluate(_route_or_decision, _opts), do: {:error, :invalid_reflex_input}

  @spec classify(map(), keyword()) :: {:ok, confidence_class()} | {:error, term()}
  def classify(route_or_decision, opts \\ []) do
    with {:ok, result} <- evaluate(route_or_decision, opts), do: {:ok, result.confidence_class}
  end

  @spec defaults(keyword()) :: map()
  def defaults(opts \\ [])

  def defaults(opts) when is_list(opts) do
    profile = Keyword.get(opts, :runtime_profile, :cuda_exla)

    mode =
      case normalize_margin_mode(Keyword.get(opts, :reflex_margin_mode, :profile_floor)) do
        {:ok, value} -> value
        {:error, _reason} -> :profile_floor
      end

    %{
      enabled?: true,
      margin_mode: mode,
      missing_margin: :medium,
      force_sequence: @default_force_sequence,
      thresholds: default_thresholds(mode, profile)
    }
  end

  def defaults(_opts), do: defaults([])

  defp config(route, opts) do
    profile = runtime_profile(route)

    with {:ok, enabled?} <- normalize_enabled(Keyword.get(opts, :reflex_enabled?, true)),
         {:ok, mode} <-
           normalize_margin_mode(Keyword.get(opts, :reflex_margin_mode, :profile_floor)),
         {:ok, missing_margin} <-
           normalize_missing_margin(Keyword.get(opts, :reflex_missing_margin, :medium)),
         {:ok, force_sequence} <-
           normalize_force_sequence(
             Keyword.get(opts, :reflex_force_sequence, @default_force_sequence)
           ),
         {:ok, thresholds} <- thresholds(mode, profile, opts) do
      {:ok,
       %{
         enabled?: enabled?,
         margin_mode: mode,
         missing_margin: missing_margin,
         force_sequence: force_sequence,
         thresholds: thresholds
       }}
    end
  end

  defp classification(route, config) do
    {agent_margin, role_margin} = margins(route)
    band = confidence_band(route)

    class =
      cond do
        low_band?(band) ->
          :low

        not is_number(agent_margin) or not is_number(role_margin) ->
          config.missing_margin

        agent_margin < config.thresholds.low_agent or
            role_margin < config.thresholds.low_role ->
          :low

        agent_margin >= config.thresholds.high_agent and
            role_margin >= config.thresholds.high_role ->
          :high

        true ->
          :medium
      end

    {:ok, class}
  end

  defp explanation(route, config, classification) do
    {agent_margin, role_margin} = margins(route)
    enabled? = config.enabled?

    %{
      enabled?: enabled?,
      confidence_class: classification,
      action: action(classification, enabled?),
      reason: reason(route, classification, enabled?),
      min_margin: min_margin(agent_margin, role_margin),
      agent_margin: number_or_nil(agent_margin),
      role_margin: number_or_nil(role_margin),
      confidence_band: confidence_band(route),
      thresholds: config.thresholds,
      next_role_override: next_role_override(route, classification, enabled?),
      forced_sequence: forced_sequence(config, classification, enabled?)
    }
  end

  defp action(_class, false), do: :normal_dispatch
  defp action(:high, true), do: :direct_dispatch
  defp action(:medium, true), do: :normal_dispatch
  defp action(:low, true), do: :thinker_then_verifier

  defp reason(_route, _class, false), do: :disabled

  defp reason(route, :low, true) do
    {agent_margin, role_margin} = margins(route)

    if is_number(agent_margin) and is_number(role_margin),
      do: :low_margin,
      else: :missing_margin
  end

  defp reason(_route, :high, true), do: :high_confidence
  defp reason(_route, :medium, true), do: :medium_confidence

  defp forced_sequence(config, :low, true), do: config.force_sequence
  defp forced_sequence(_config, _class, _enabled?), do: []

  defp next_role_override(route, :low, true) do
    case role_atom(route) do
      :thinker -> RoleInjector.role_id(:verifier)
      :verifier -> nil
      _other -> RoleInjector.role_id(:thinker)
    end
  end

  defp next_role_override(_route, _class, _enabled?), do: nil

  defp thresholds(mode, profile, opts) do
    base = default_thresholds(mode, profile)

    with {:ok, high_agent} <-
           threshold(opts, :reflex_high_agent_margin, base.high_agent),
         {:ok, high_role} <- threshold(opts, :reflex_high_role_margin, base.high_role),
         {:ok, low_agent} <- threshold(opts, :reflex_low_agent_margin, base.low_agent),
         {:ok, low_role} <- threshold(opts, :reflex_low_role_margin, base.low_role) do
      {:ok,
       %{
         high_agent: high_agent,
         high_role: high_role,
         low_agent: low_agent,
         low_role: low_role
       }}
    end
  end

  defp default_thresholds(:absolute, _profile), do: @absolute_thresholds

  defp default_thresholds(:profile_floor, profile) do
    floor = MarginDefaults.defaults(profile)

    %{
      high_agent: floor.agent * 4.0,
      high_role: floor.role * 4.0,
      low_agent: floor.agent,
      low_role: floor.role
    }
  end

  defp threshold(opts, key, default) do
    case Keyword.get(opts, key) do
      nil -> {:ok, default}
      value when is_number(value) and value >= 0 -> {:ok, value * 1.0}
      value -> {:error, {:invalid_reflex_threshold, key, value}}
    end
  end

  defp normalize_enabled(value) when is_boolean(value), do: {:ok, value}
  defp normalize_enabled(value), do: {:error, {:invalid_reflex_enabled, value}}

  defp normalize_margin_mode(:profile_floor), do: {:ok, :profile_floor}
  defp normalize_margin_mode("profile_floor"), do: {:ok, :profile_floor}
  defp normalize_margin_mode(:absolute), do: {:ok, :absolute}
  defp normalize_margin_mode("absolute"), do: {:ok, :absolute}
  defp normalize_margin_mode(value), do: {:error, {:invalid_reflex_margin_mode, value}}

  defp normalize_missing_margin(:medium), do: {:ok, :medium}
  defp normalize_missing_margin("medium"), do: {:ok, :medium}
  defp normalize_missing_margin(:low), do: {:ok, :low}
  defp normalize_missing_margin("low"), do: {:ok, :low}

  defp normalize_missing_margin(value),
    do: {:error, {:invalid_reflex_missing_margin, value}}

  defp normalize_force_sequence(@default_force_sequence), do: {:ok, @default_force_sequence}

  defp normalize_force_sequence(value),
    do: {:error, {:invalid_reflex_force_sequence, value}}

  defp margins(route) do
    decision = field(route, :decision, route)
    margin_map = field(decision, :margins, field(route, :margins, %{})) || %{}
    {field(margin_map, :agent), field(margin_map, :role)}
  end

  defp confidence_band(route) do
    decision = field(route, :decision, route)

    decision
    |> field(:confidence_band, field(route, :confidence_band))
    |> normalize_confidence_band()
  end

  defp normalize_confidence_band(:high), do: :high
  defp normalize_confidence_band("high"), do: :high
  defp normalize_confidence_band(:medium), do: :medium
  defp normalize_confidence_band("medium"), do: :medium
  defp normalize_confidence_band(:low), do: :low
  defp normalize_confidence_band("low"), do: :low
  defp normalize_confidence_band(:uncertain), do: :uncertain
  defp normalize_confidence_band("uncertain"), do: :uncertain
  defp normalize_confidence_band(:unknown), do: :unknown
  defp normalize_confidence_band("unknown"), do: :unknown
  defp normalize_confidence_band(_value), do: nil

  defp low_band?(band), do: band in [:low, :uncertain]

  defp runtime_profile(route) do
    decision = field(route, :decision, route)
    field(decision, :runtime_profile, field(route, :runtime_profile, :cuda_exla))
  end

  defp role_atom(route) do
    role =
      field(route, :role_atom) || field(route, :role_name) || field(route, :selected_role_id) ||
        route |> field(:decision, %{}) |> field(:selected_role_id)

    RoleInjector.role_atom(role)
  end

  defp min_margin(left, right) when is_number(left) and is_number(right), do: min(left, right)
  defp min_margin(_left, _right), do: nil

  defp number_or_nil(value) when is_number(value), do: value
  defp number_or_nil(_value), do: nil

  defp field(map, key, default \\ nil)

  defp field(map, key, default) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp field(_map, _key, default), do: default
end
