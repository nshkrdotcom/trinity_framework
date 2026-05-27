defmodule Trinity.Coordinator.Orchestrator do
  @moduledoc """
  Behavior-injected TRINITY coordinator loop.
  """

  alias CruciblePolicy.RouteDecision, as: CrucibleRouteDecision

  alias Trinity.Coordinator.{
    AgentCallIntent,
    AgentCallReceipt,
    Budgets,
    HiddenStateExtractionPlan,
    RoleInjector,
    RouteDecisionDerivation,
    RouteLogits,
    RunGovernance,
    StateManager,
    Thinker,
    Verifier
  }

  @default_max_turns 5

  @spec run_loop(pid() | [map()], keyword()) :: {:ok, map()} | {:error, term()}
  def run_loop(messages_or_pid, opts \\ []) when is_list(opts) do
    with {:ok, pid} <- state_pid(messages_or_pid),
         {:ok, opts} <- RunGovernance.materialize_orchestrator_opts(opts),
         {:ok, run_ctx} <- run_context(opts) do
      do_loop(pid, run_ctx)
    end
  end

  @spec check_budgets(map(), atom(), map()) :: :ok | {:budget_exceeded, atom(), map()}
  defdelegate check_budgets(run_ctx, checkpoint, extras \\ %{}), to: Budgets, as: :check

  defp do_loop(pid, run_ctx) do
    loop_state = %{latest_worker_response: nil, next_role_override: nil}
    turn(pid, run_ctx, loop_state, 0)
  end

  defp turn(pid, run_ctx, loop_state, turn) do
    cond do
      turn >= run_ctx.max_turns and is_binary(loop_state.latest_worker_response) ->
        {:ok, result(pid, loop_state.latest_worker_response, turn)}

      turn >= run_ctx.max_turns ->
        {:error, :max_turns_reached}

      true ->
        do_turn(pid, run_ctx, loop_state, turn)
    end
  end

  defp do_turn(pid, run_ctx, loop_state, turn) do
    with :ok <-
           normalize_budget(Budgets.check(run_ctx.budget_context, :turn_start, %{turn: turn})),
         messages <- StateManager.get_messages(pid),
         {:ok, route_result} <- route(messages, run_ctx, turn),
         {:ok, decision} <- derive_route_decision(route_result, messages, run_ctx.decision_attrs),
         route <- apply_role_override(decision, loop_state),
         :ok <- ensure_role_dispatch_allowed(route.role_atom, loop_state),
         :ok <-
           normalize_budget(
             Budgets.bump_provider_call(run_ctx.budget_context, :before_dispatch, %{turn: turn})
           ),
         {:ok, response_text, receipt, latency_ms} <- dispatch(messages, route, run_ctx, turn),
         :ok <-
           normalize_budget(
             Budgets.check_provider_latency(run_ctx.budget_context, latency_ms, %{turn: turn})
           ),
         :ok <- budget_cost(run_ctx, receipt),
         :ok <- StateManager.append_assistant(pid, response_text),
         {:cont, next_state} <-
           handle_role_response(route, response_text, loop_state, run_ctx, turn) do
      turn(pid, run_ctx, next_state, turn + 1)
    else
      {:halt, response_text} -> {:ok, result(pid, response_text, turn + 1)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp route(messages, run_ctx, turn) do
    opts = [messages: messages, turn: turn]
    run_ctx.model_runtime.route(run_ctx.model_state, run_ctx.extraction_plan, opts)
  end

  defp derive_route_decision(%RouteLogits{} = route_logits, messages, attrs) do
    RouteDecisionDerivation.from_logits(route_logits, messages, attrs)
  end

  defp derive_route_decision(%CrucibleRouteDecision{} = route_decision, messages, attrs) do
    RouteDecisionDerivation.from_crucible(route_decision, messages, attrs)
  end

  defp dispatch(messages, route, run_ctx, turn) do
    intent = %AgentCallIntent{
      intent_ref: "agent-intent:#{turn}",
      role_ref: Atom.to_string(route.role_atom),
      agent_ref: "agent:#{route.selected_agent_id}",
      messages: RoleInjector.inject_role(messages, route.role_atom),
      metadata: %{turn: turn, route_decision: route.decision}
    }

    started = System.monotonic_time(:millisecond)

    with {:ok, %AgentCallReceipt{} = receipt} <-
           run_ctx.agent_caller.call(intent, run_ctx.agent_opts),
         {:ok, text} <- receipt_text(receipt) do
      {:ok, text, receipt, elapsed_ms(started)}
    end
  end

  defp handle_role_response(%{role_atom: :verifier}, response_text, loop_state, run_ctx, turn) do
    parsed = Verifier.parse(response_text)

    if Verifier.safe_status(parsed) == :accepted do
      {:halt, response_text}
    else
      case Budgets.bump_verifier_revision(run_ctx.budget_context, %{turn: turn}) do
        :ok -> {:cont, loop_state}
        {:budget_exceeded, kind, details} -> {:error, {:budget_exceeded, kind, details}}
      end
    end
  end

  defp handle_role_response(%{role_atom: :thinker}, response_text, loop_state, _run_ctx, _turn) do
    case Thinker.parse(response_text) do
      %Thinker{suggested_role_id: role_id} when is_integer(role_id) ->
        {:cont, %{loop_state | next_role_override: role_id}}

      _ ->
        {:cont, loop_state}
    end
  end

  defp handle_role_response(%{role_atom: :worker}, response_text, loop_state, _run_ctx, _turn) do
    {:cont, %{loop_state | latest_worker_response: response_text, next_role_override: nil}}
  end

  defp handle_role_response(_route, _response_text, loop_state, _run_ctx, _turn),
    do: {:cont, loop_state}

  defp apply_role_override(decision, %{next_role_override: role_id}) when is_integer(role_id) do
    %{
      route_from_decision(decision)
      | selected_role_id: role_id,
        role_name: RoleInjector.role_name(role_id),
        role_atom: RoleInjector.role_atom(role_id)
    }
  end

  defp apply_role_override(decision, _loop_state), do: route_from_decision(decision)

  defp route_from_decision(decision) do
    role_name = decision.role_name || RoleInjector.role_name(decision.selected_role_id)

    %{
      decision: decision,
      selected_agent_id: decision.selected_agent_id,
      selected_role_id: decision.selected_role_id,
      role_name: role_name,
      role_atom: RoleInjector.role_atom(role_name)
    }
  end

  defp ensure_role_dispatch_allowed(:verifier, %{latest_worker_response: nil}),
    do: {:error, :verifier_before_worker_response}

  defp ensure_role_dispatch_allowed(_role, _state), do: :ok

  defp receipt_text(%AgentCallReceipt{status: status, metadata: metadata})
       when status in [:ok, :complete] do
    case Map.get(metadata, :text, Map.get(metadata, "text")) do
      text when is_binary(text) -> {:ok, text}
      _ -> {:error, :missing_agent_response_text}
    end
  end

  defp receipt_text(%AgentCallReceipt{status: status}), do: {:error, {:agent_call_failed, status}}

  defp budget_cost(run_ctx, receipt) do
    Budgets.bump_estimated_cost(run_ctx.budget_context, receipt)
    normalize_budget(Budgets.check(run_ctx.budget_context, :after_dispatch, %{}))
  end

  defp normalize_budget(:ok), do: :ok

  defp normalize_budget({:budget_exceeded, kind, details}),
    do: {:error, {:budget_exceeded, kind, details}}

  defp run_context(opts) do
    with {:ok, model_runtime} <- behaviour_module(opts, :model_runtime),
         {:ok, agent_caller} <- behaviour_module(opts, :agent_caller) do
      {:ok,
       %{
         model_runtime: model_runtime,
         agent_caller: agent_caller,
         model_state: Keyword.get(opts, :model_state),
         extraction_plan: Keyword.get(opts, :extraction_plan, default_extraction_plan()),
         agent_opts: Keyword.get(opts, :agent_opts, []),
         max_turns: Keyword.get(opts, :max_turns, @default_max_turns),
         budget_context: Budgets.new_context(opts),
         decision_attrs: Keyword.get(opts, :decision_attrs, [])
       }}
    end
  end

  defp behaviour_module(opts, key) do
    case Keyword.get(opts, key) do
      module when is_atom(module) and not is_nil(module) -> {:ok, module}
      nil -> {:error, {:missing_behaviour_module, key}}
      other -> {:error, {:invalid_behaviour_module, key, other}}
    end
  end

  defp state_pid(pid) when is_pid(pid), do: {:ok, pid}

  defp state_pid(messages) when is_list(messages) do
    case StateManager.start_link(messages) do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  defp state_pid(_), do: {:error, :invalid_messages_or_state}

  defp default_extraction_plan do
    %HiddenStateExtractionPlan{
      adapter_ref: "adapter:core",
      messages: []
    }
  end

  defp result(pid, response, turns),
    do: %{response: response, messages: StateManager.get_messages(pid), turns: turns}

  defp elapsed_ms(started), do: max(System.monotonic_time(:millisecond) - started, 0)
end
