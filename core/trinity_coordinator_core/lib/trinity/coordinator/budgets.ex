defmodule Trinity.Coordinator.Budgets do
  @moduledoc """
  Budget counters and halt decisions for coordinator-core runs.
  """

  require Logger

  @budget_keys [
    :max_wall_time_ms,
    :max_provider_calls,
    :max_provider_latency_ms,
    :max_verifier_revisions,
    :max_estimated_cost_usd,
    :cost_estimator_fn
  ]

  @spec keys() :: [atom()]
  def keys, do: @budget_keys

  @spec new_context(keyword() | map()) :: map()
  def new_context(opts \\ []) do
    opts = if is_map(opts), do: Map.to_list(opts), else: opts

    %{
      budgets: budgets_from(opts),
      cost_estimator_fn: Keyword.get(opts, :cost_estimator_fn),
      counters: %{
        started_monotonic_ms: System.monotonic_time(:millisecond),
        provider_calls_ref: :counters.new(1, [:atomics]),
        verifier_revisions_ref: :counters.new(1, [:atomics]),
        estimated_cost_micro_usd_ref: :counters.new(1, [:atomics]),
        cost_warning_emitted_ref: :counters.new(1, [:atomics])
      }
    }
  end

  @spec check(map(), atom(), map()) :: :ok | {:budget_exceeded, atom(), map()}
  def check(run_ctx, checkpoint, extras \\ %{}) when is_map(run_ctx) and is_atom(checkpoint) do
    budgets = Map.get(run_ctx, :budgets, %{})
    counters = Map.get(run_ctx, :counters, %{})

    cond do
      exceeded_wall_time?(budgets, counters) ->
        exceeded(:wall_time, wall_time_details(budgets, counters, checkpoint, extras))

      exceeded_provider_calls?(budgets, counters) ->
        exceeded(:provider_calls, provider_details(budgets, counters, checkpoint, extras))

      exceeded_verifier_revisions?(budgets, counters) ->
        exceeded(:verifier_revisions, revision_details(budgets, counters, checkpoint, extras))

      exceeded_cost?(budgets, counters) ->
        exceeded(:estimated_cost_usd, cost_details(budgets, counters, checkpoint, extras))

      true ->
        :ok
    end
  end

  @spec bump_provider_call(map(), atom(), map()) :: :ok | {:budget_exceeded, atom(), map()}
  def bump_provider_call(run_ctx, checkpoint \\ :before_dispatch, extras \\ %{}) do
    bump_counter(run_ctx, :provider_calls_ref)
    check(run_ctx, checkpoint, extras)
  end

  @spec check_provider_latency(map(), non_neg_integer(), map()) ::
          :ok | {:budget_exceeded, :provider_latency_ms, map()}
  def check_provider_latency(run_ctx, latency_ms, extras \\ %{}) when is_integer(latency_ms) do
    case get_in(run_ctx, [:budgets, :max_provider_latency_ms]) do
      limit when is_integer(limit) and latency_ms > limit ->
        {:budget_exceeded, :provider_latency_ms,
         Map.merge(
           %{limit_ms: limit, observed_ms: latency_ms, checkpoint: :after_dispatch},
           Map.new(extras)
         )}

      _ ->
        :ok
    end
  end

  @spec bump_estimated_cost(map(), term()) :: :ok
  def bump_estimated_cost(run_ctx, dispatch) do
    case {get_in(run_ctx, [:budgets, :max_estimated_cost_usd]),
          Map.get(run_ctx, :cost_estimator_fn)} do
      {nil, _fun} -> :ok
      {_limit, fun} when is_function(fun, 1) -> bump_cost(run_ctx, fun.(dispatch))
      {_limit, _missing} -> maybe_warn_missing_cost_estimator(run_ctx)
    end
  end

  @spec bump_verifier_revision(map(), map()) ::
          :ok | {:budget_exceeded, :verifier_revisions, map()}
  def bump_verifier_revision(run_ctx, extras \\ %{}) do
    bump_counter(run_ctx, :verifier_revisions_ref)

    case check(run_ctx, :after_verifier_revision, extras) do
      {:budget_exceeded, :verifier_revisions, details} ->
        {:budget_exceeded, :verifier_revisions, details}

      _ ->
        :ok
    end
  end

  @doc "Returns a trace-safe snapshot of current counters and budget state."
  @spec snapshot(map(), atom(), map()) :: map()
  def snapshot(run_ctx, checkpoint, extras \\ %{})
      when is_map(run_ctx) and is_atom(checkpoint) and is_map(extras) do
    counters = Map.get(run_ctx, :counters, %{})

    %{
      checkpoint: checkpoint,
      provider_calls: provider_call_count(counters),
      verifier_revisions: verifier_revision_count(counters),
      estimated_cost_usd: estimated_cost_usd(counters),
      wall_time_ms: elapsed_ms(counters[:started_monotonic_ms] || 0),
      budget_exceeded: Map.get(extras, :budget_exceeded, false),
      budget_exceeded_key: Map.get(extras, :budget_exceeded_key)
    }
    |> Map.merge(Map.drop(extras, [:budget_exceeded, :budget_exceeded_key]))
  end

  defp budgets_from(opts) do
    Map.new(@budget_keys -- [:cost_estimator_fn], &{&1, Keyword.get(opts, &1)})
  end

  defp exceeded(kind, details), do: {:budget_exceeded, kind, details}

  defp exceeded_wall_time?(%{max_wall_time_ms: nil}, _), do: false

  defp exceeded_wall_time?(%{max_wall_time_ms: limit}, counters) when is_integer(limit),
    do: elapsed_ms(counters[:started_monotonic_ms] || 0) >= limit

  defp exceeded_wall_time?(_, _), do: false

  defp exceeded_provider_calls?(%{max_provider_calls: nil}, _), do: false

  defp exceeded_provider_calls?(%{max_provider_calls: limit}, counters) when is_integer(limit),
    do: provider_call_count(counters) > limit

  defp exceeded_provider_calls?(_, _), do: false

  defp exceeded_verifier_revisions?(%{max_verifier_revisions: nil}, _), do: false

  defp exceeded_verifier_revisions?(%{max_verifier_revisions: limit}, counters)
       when is_integer(limit),
       do: verifier_revision_count(counters) > limit

  defp exceeded_verifier_revisions?(_, _), do: false

  defp exceeded_cost?(%{max_estimated_cost_usd: nil}, _), do: false

  defp exceeded_cost?(%{max_estimated_cost_usd: limit}, counters) when is_number(limit),
    do: estimated_cost_usd(counters) >= limit

  defp exceeded_cost?(_, _), do: false

  defp wall_time_details(budgets, counters, checkpoint, extras),
    do:
      Map.merge(
        %{
          limit_ms: budgets[:max_wall_time_ms],
          elapsed_ms: elapsed_ms(counters[:started_monotonic_ms] || 0),
          checkpoint: checkpoint
        },
        extras
      )

  defp provider_details(budgets, counters, checkpoint, extras),
    do:
      Map.merge(
        %{
          limit: budgets[:max_provider_calls],
          observed: provider_call_count(counters),
          checkpoint: checkpoint
        },
        extras
      )

  defp revision_details(budgets, counters, checkpoint, extras),
    do:
      Map.merge(
        %{
          limit: budgets[:max_verifier_revisions],
          observed: verifier_revision_count(counters),
          checkpoint: checkpoint
        },
        extras
      )

  defp cost_details(budgets, counters, checkpoint, extras),
    do:
      Map.merge(
        %{
          limit_usd: budgets[:max_estimated_cost_usd],
          observed_usd: estimated_cost_usd(counters),
          checkpoint: checkpoint
        },
        extras
      )

  defp bump_counter(run_ctx, counter_key) do
    case get_in(run_ctx, [:counters, counter_key]) do
      nil -> :ok
      ref -> :counters.add(ref, 1, 1)
    end
  end

  defp bump_cost(_run_ctx, cost_usd) when not is_number(cost_usd) or cost_usd < 0, do: :ok

  defp bump_cost(run_ctx, cost_usd) do
    case get_in(run_ctx, [:counters, :estimated_cost_micro_usd_ref]) do
      nil -> :ok
      ref -> :counters.add(ref, 1, round(cost_usd * 1_000_000))
    end
  end

  defp maybe_warn_missing_cost_estimator(run_ctx) do
    case get_in(run_ctx, [:counters, :cost_warning_emitted_ref]) do
      nil ->
        :ok

      ref ->
        if :counters.get(ref, 1) == 0 do
          :counters.add(ref, 1, 1)

          Logger.warning(
            "max_estimated_cost_usd was set but no cost_estimator_fn was provided; cost budget will not fire."
          )
        end

        :ok
    end
  end

  defp provider_call_count(%{provider_calls_ref: ref}), do: :counters.get(ref, 1)
  defp provider_call_count(_), do: 0
  defp verifier_revision_count(%{verifier_revisions_ref: ref}), do: :counters.get(ref, 1)
  defp verifier_revision_count(_), do: 0

  defp estimated_cost_usd(%{estimated_cost_micro_usd_ref: ref}),
    do: :counters.get(ref, 1) / 1_000_000

  defp estimated_cost_usd(_), do: 0.0
  defp elapsed_ms(start), do: max(System.monotonic_time(:millisecond) - start, 0)
end
