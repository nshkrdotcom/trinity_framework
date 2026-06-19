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
    TraceEvent,
    Verifier
  }

  @default_max_turns 5

  @spec run_loop(pid() | [map()], keyword()) :: {:ok, map()} | {:error, term()}
  def run_loop(messages_or_pid, opts \\ []) when is_list(opts) do
    with {:ok, pid} <- state_pid(messages_or_pid),
         {:ok, opts} <- RunGovernance.materialize_orchestrator_opts(opts),
         {:ok, run_ctx} <- run_context(opts) do
      pid
      |> do_loop(run_ctx)
      |> finish_run(run_ctx)
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
    with :ok <- check_budget(run_ctx, :turn_start, %{turn: turn}),
         messages <- StateManager.get_messages(pid),
         {:ok, route_result} <- route(messages, run_ctx, turn),
         {:ok, decision} <- derive_route_decision(route_result, messages, run_ctx.decision_attrs),
         route <- apply_role_override(decision, loop_state),
         :ok <- emit_route_decision(run_ctx, route, messages, turn),
         :ok <- ensure_role_dispatch_allowed(route.role_atom, loop_state),
         :ok <- bump_provider_call(run_ctx, turn),
         {:ok, response_text, receipt, latency_ms} <- dispatch(messages, route, run_ctx, turn),
         :ok <- check_provider_latency(run_ctx, latency_ms, turn),
         :ok <- budget_cost(run_ctx, receipt, turn),
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
    plan = route_plan(run_ctx.extraction_plan, messages)
    run_ctx.model_runtime.route(run_ctx.model_state, plan, opts)
  end

  defp route_plan(%HiddenStateExtractionPlan{} = plan, messages), do: %{plan | messages: messages}
  defp route_plan(plan, _messages), do: plan

  defp derive_route_decision(%RouteLogits{} = route_logits, messages, attrs) do
    RouteDecisionDerivation.from_logits(route_logits, messages, attrs)
  end

  defp derive_route_decision(%CrucibleRouteDecision{} = route_decision, messages, attrs) do
    RouteDecisionDerivation.from_crucible(route_decision, messages, attrs)
  end

  defp dispatch(messages, route, run_ctx, turn) do
    dispatch_ref = "dispatch:#{run_ctx.coordination_run_ref}:#{turn}"
    dispatch_metadata = dispatch_metadata(run_ctx, route)

    intent = %AgentCallIntent{
      intent_ref: dispatch_ref,
      role_ref: Atom.to_string(route.role_atom),
      agent_ref: "agent:#{route.selected_agent_id}",
      messages: RoleInjector.inject_role(messages, route.role_atom),
      metadata: %{turn: turn, route_decision: route.decision}
    }

    started = System.monotonic_time(:millisecond)

    with :ok <-
           emit_event(
             run_ctx,
             :provider_dispatch_started,
             dispatch_payload(route, turn, dispatch_ref, dispatch_metadata)
           ) do
      caller = run_ctx.agent_caller
      call_result = caller.call(intent, run_ctx.agent_opts)
      finish_dispatch(call_result, run_ctx, route, turn, dispatch_ref, dispatch_metadata, started)
    end
  end

  defp finish_dispatch(
         {:ok, %AgentCallReceipt{} = receipt},
         run_ctx,
         route,
         turn,
         dispatch_ref,
         metadata,
         started
       ) do
    latency_ms = elapsed_ms(started)

    case receipt_text(receipt) do
      {:ok, text} ->
        with :ok <-
               emit_dispatch_finished(
                 run_ctx,
                 route,
                 turn,
                 dispatch_ref,
                 metadata,
                 %{receipt: receipt, latency_ms: latency_ms, ok: true, error_ref: nil}
               ) do
          {:ok, text, receipt, latency_ms}
        end

      {:error, reason} ->
        finish_failed_dispatch(
          run_ctx,
          route,
          turn,
          dispatch_ref,
          metadata,
          receipt,
          latency_ms,
          reason
        )
    end
  end

  defp finish_dispatch(
         {:error, reason},
         run_ctx,
         route,
         turn,
         dispatch_ref,
         metadata,
         started
       ) do
    finish_failed_dispatch(
      run_ctx,
      route,
      turn,
      dispatch_ref,
      metadata,
      nil,
      elapsed_ms(started),
      reason
    )
  end

  defp finish_failed_dispatch(
         run_ctx,
         route,
         turn,
         dispatch_ref,
         metadata,
         receipt,
         latency_ms,
         reason
       ) do
    with :ok <-
           emit_dispatch_finished(
             run_ctx,
             route,
             turn,
             dispatch_ref,
             metadata,
             %{
               receipt: receipt,
               latency_ms: latency_ms,
               ok: false,
               error_ref: reason_ref(reason)
             }
           ) do
      {:error, reason}
    end
  end

  defp emit_dispatch_finished(
         run_ctx,
         route,
         turn,
         dispatch_ref,
         metadata,
         completion
       ) do
    payload =
      dispatch_finished_payload(
        route,
        turn,
        dispatch_ref,
        metadata,
        completion.receipt,
        completion.latency_ms,
        completion.ok,
        completion.error_ref
      )

    emit_event(run_ctx, :provider_dispatch_finished, payload)
  end

  defp handle_role_response(
         %{role_atom: :verifier} = route,
         response_text,
         loop_state,
         run_ctx,
         turn
       ) do
    parsed = Verifier.parse(response_text)

    with :ok <- emit_verifier_result(run_ctx, route, parsed, response_text, turn) do
      handle_verifier_status(parsed, response_text, loop_state, run_ctx, turn)
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

  defp handle_verifier_status(parsed, response_text, loop_state, run_ctx, turn) do
    if Verifier.safe_status(parsed) == :accepted do
      {:halt, response_text}
    else
      case bump_verifier_revision(run_ctx, turn) do
        :ok -> {:cont, loop_state}
        {:error, reason} -> {:error, reason}
      end
    end
  end

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

  defp budget_cost(run_ctx, receipt, turn) do
    Budgets.bump_estimated_cost(run_ctx.budget_context, receipt)
    check_budget(run_ctx, :after_dispatch, %{turn: turn})
  end

  defp check_budget(run_ctx, checkpoint, extras) do
    run_ctx.budget_context
    |> Budgets.check(checkpoint, extras)
    |> trace_budget_result(run_ctx, checkpoint, extras)
  end

  defp bump_provider_call(run_ctx, turn) do
    run_ctx.budget_context
    |> Budgets.bump_provider_call(:before_dispatch, %{turn: turn})
    |> trace_budget_result(run_ctx, :before_dispatch, %{turn: turn})
  end

  defp check_provider_latency(run_ctx, latency_ms, turn) do
    run_ctx.budget_context
    |> Budgets.check_provider_latency(latency_ms, %{turn: turn})
    |> trace_budget_result(run_ctx, :after_dispatch_latency, %{
      turn: turn,
      observed_latency_ms: latency_ms
    })
  end

  defp bump_verifier_revision(run_ctx, turn) do
    run_ctx.budget_context
    |> Budgets.bump_verifier_revision(%{turn: turn})
    |> trace_budget_result(run_ctx, :after_verifier_revision, %{turn: turn})
  end

  defp trace_budget_result(:ok, run_ctx, checkpoint, extras) do
    emit_budget_snapshot(run_ctx, checkpoint, extras)
  end

  defp trace_budget_result({:budget_exceeded, kind, details}, run_ctx, checkpoint, extras) do
    payload_extras =
      extras
      |> Map.put(:budget_exceeded, true)
      |> Map.put(:budget_exceeded_key, kind)

    case emit_budget_snapshot(run_ctx, checkpoint, payload_extras) do
      :ok -> {:error, {:budget_exceeded, kind, details}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp emit_budget_snapshot(run_ctx, checkpoint, extras) do
    payload =
      run_ctx.budget_context
      |> Budgets.snapshot(checkpoint, extras)
      |> Map.put_new(:turn, Map.get(extras, :turn))

    emit_event(run_ctx, :budget_snapshot, payload)
  end

  defp emit_route_decision(run_ctx, route, messages, turn) do
    decision = route.decision
    identity = decision.artifact_identity || %{}
    margins = decision.margins || %{}

    payload = %{
      turn: turn,
      selected_agent_id: route.selected_agent_id,
      selected_role_id: route.selected_role_id,
      role_name: route.role_name,
      agent_margin: map_field(margins, :agent),
      role_margin: map_field(margins, :role),
      min_margin: min_number(map_field(margins, :agent), map_field(margins, :role)),
      confidence_band: decision.confidence_band,
      token_count: decision.token_count,
      transcript_hash: decision.transcript_hash,
      route_hash: decision.route_hash,
      runtime_profile: decision.runtime_profile,
      provider_pool: run_ctx.provider_pool,
      route_path: run_ctx.route_path,
      artifact_ref: map_field(identity, :artifact_ref) || decision.router_artifact_ref,
      artifact_revision: map_field(identity, :artifact_revision),
      artifact_hash_ref:
        map_field(identity, :artifact_manifest_sha256_actual) ||
          map_field(identity, :artifact_manifest_sha256),
      input_hash: decision.transcript_hash
    }

    payload =
      if run_ctx.trace_content == :full,
        do: Map.put(payload, :input_content, messages),
        else: payload

    emit_event(run_ctx, :route_decision, payload)
  end

  defp emit_verifier_result(run_ctx, route, parsed, response_text, turn) do
    snapshot = Budgets.snapshot(run_ctx.budget_context, :verifier_result, %{turn: turn})

    payload = %{
      turn: turn,
      route_hash: route.decision.route_hash,
      selected_agent_id: route.selected_agent_id,
      selected_role_id: route.selected_role_id,
      status: verifier_status(parsed.status),
      safe_status: Verifier.safe_status(parsed),
      revision_count: snapshot.verifier_revisions,
      verifier_response_ref: hash_ref("verifier-response", response_text)
    }

    emit_event(run_ctx, :verifier_result, payload)
  end

  defp finish_run({:ok, result} = outcome, run_ctx) do
    snapshot = Budgets.snapshot(run_ctx.budget_context, :run_finished)

    payload = %{
      status: :finished,
      total_turns: result.turns,
      final_response_ref: hash_ref("response", result.response),
      provider_calls: snapshot.provider_calls,
      verifier_revisions: snapshot.verifier_revisions,
      estimated_cost_usd: snapshot.estimated_cost_usd,
      wall_time_ms: snapshot.wall_time_ms
    }

    case emit_event(run_ctx, :run_finished, payload) do
      :ok -> outcome
      {:error, reason} -> {:error, reason}
    end
  end

  defp finish_run({:error, reason} = outcome, run_ctx) do
    snapshot = Budgets.snapshot(run_ctx.budget_context, :run_failed)

    payload = %{
      status: :failed,
      reason_ref: reason_ref(reason),
      provider_calls: snapshot.provider_calls,
      verifier_revisions: snapshot.verifier_revisions,
      estimated_cost_usd: snapshot.estimated_cost_usd,
      wall_time_ms: snapshot.wall_time_ms,
      budget_exceeded_key: budget_exceeded_key(reason)
    }

    case emit_event(run_ctx, :run_failed, payload) do
      :ok -> outcome
      {:error, emit_reason} -> {:error, {:trace_emit_failed, emit_reason, reason_ref(reason)}}
    end
  end

  defp dispatch_payload(route, turn, dispatch_ref, metadata) do
    %{
      turn: turn,
      selected_agent_id: route.selected_agent_id,
      selected_role_id: route.selected_role_id,
      provider_pool: map_field(metadata, :provider_pool),
      provider: map_field(metadata, :provider),
      model: map_field(metadata, :model),
      model_profile: map_field(metadata, :model_profile),
      dispatch_ref: dispatch_ref
    }
  end

  defp dispatch_finished_payload(
         route,
         turn,
         dispatch_ref,
         metadata,
         receipt,
         latency_ms,
         ok,
         error_ref
       ) do
    receipt_metadata = if match?(%AgentCallReceipt{}, receipt), do: receipt.metadata, else: %{}

    dispatch_payload(route, turn, dispatch_ref, metadata)
    |> Map.put(
      :provider,
      map_field(receipt_metadata, :provider) || map_field(metadata, :provider)
    )
    |> Map.put(:model, map_field(receipt_metadata, :model) || map_field(metadata, :model))
    |> Map.put(:response_ref, receipt && receipt.response_ref)
    |> Map.put(:latency_ms, latency_ms)
    |> Map.put(:estimated_cost_usd, map_field(receipt_metadata, :estimated_cost_usd))
    |> Map.put(:ok, ok)
    |> Map.put(:error_ref, error_ref)
  end

  defp dispatch_metadata(%{dispatch_metadata_fn: fun} = run_ctx, route)
       when is_function(fun, 1) do
    route
    |> fun.()
    |> normalize_map()
    |> Map.put_new(:provider_pool, run_ctx.provider_pool)
  end

  defp dispatch_metadata(run_ctx, _route), do: %{provider_pool: run_ctx.provider_pool}

  defp emit_event(%{trace_sink: nil}, _event_type, _payload), do: :ok

  defp emit_event(run_ctx, event_type, payload) do
    event = %TraceEvent{
      event_ref: "trace-event:#{event_type}:#{System.unique_integer([:positive, :monotonic])}",
      event_type: event_type,
      trace_ref: run_ctx.trace_ref,
      coordination_run_ref: run_ctx.coordination_run_ref,
      timestamp_ms: System.system_time(:millisecond),
      payload: payload
    }

    run_ctx.trace_sink.emit(event, run_ctx.trace_opts)
  end

  defp verifier_status(:accepted), do: :accepted
  defp verifier_status(:revised), do: :revise
  defp verifier_status(:unknown), do: :unknown

  defp budget_exceeded_key({:budget_exceeded, key, _details}), do: key
  defp budget_exceeded_key(_reason), do: nil

  defp reason_ref(reason), do: hash_ref("reason", inspect(reason))

  defp hash_ref(prefix, value) do
    digest = :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
    "#{prefix}:sha256:#{digest}"
  end

  defp min_number(left, right) when is_number(left) and is_number(right), do: min(left, right)
  defp min_number(left, _right) when is_number(left), do: left
  defp min_number(_left, right) when is_number(right), do: right
  defp min_number(_left, _right), do: nil

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(value) when is_list(value), do: Map.new(value)
  defp normalize_map(_value), do: %{}

  defp map_field(map, key) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp map_field(_value, _key), do: nil

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
         decision_attrs: Keyword.get(opts, :decision_attrs, []),
         trace_sink: Keyword.get(opts, :trace_sink),
         trace_opts: Keyword.get(opts, :trace, []),
         trace_ref: Keyword.get(opts, :trace_ref),
         coordination_run_ref:
           Keyword.get(opts, :coordination_run_ref, "coordination-run:orchestrator"),
         provider_pool: Keyword.get(opts, :provider_pool),
         route_path: Keyword.get(opts, :route_path, :orchestrator),
         trace_content: Keyword.get(opts, :trace_content, :hash),
         dispatch_metadata_fn: Keyword.get(opts, :dispatch_metadata_fn)
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
