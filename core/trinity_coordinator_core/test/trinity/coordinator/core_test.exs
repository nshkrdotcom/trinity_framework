defmodule Trinity.CoordinatorCoreTest do
  use ExUnit.Case, async: true

  alias Trinity.Coordinator.{
    AgentCallIntent,
    AgentCallReceipt,
    Budgets,
    RoleInjector,
    RouteDecisionDerivation,
    RouteLogits,
    RunGovernance,
    StateManager,
    Thinker,
    Verifier
  }

  alias Trinity.Coordinator.Orchestrator

  defmodule CrucibleRuntime do
    @behaviour Trinity.Coordinator.ModelRuntime

    @impl true
    def load(plan, _opts), do: {:ok, %{plan: plan}}

    @impl true
    def route(_state, _plan, _opts) do
      {:ok,
       CruciblePolicy.RouteDecision.new!(
         trace_id: "trace-crucible",
         decision_id: "crucible-decision-1",
         selected_target: :worker,
         selected_model: :fixture_model,
         confidence: 0.82,
         uncertainty: %CruciblePolicy.Uncertainty{entropy: 0.2},
         evidence_refs: ["final_logits"]
       )}
    end
  end

  defmodule Runtime do
    @behaviour Trinity.Coordinator.ModelRuntime

    alias Trinity.Coordinator.RouteLogits

    @impl true
    def load(_plan, _opts), do: {:ok, :loaded}

    @impl true
    def route(_state, _plan, opts) do
      turn = Keyword.fetch!(opts, :turn)

      role_id =
        case turn do
          0 -> 0
          _ -> 2
        end

      {:ok, route_logits(role_id)}
    end

    def route_logits(role_id) do
      %RouteLogits{
        role_logits: [0.0, 0.0, role_score(role_id)],
        agent_logits: [1.0],
        selected_role_id: role_id,
        selected_agent_id: 0,
        token_count: 4,
        transcript_hash: String.duplicate("0", 64),
        route_hash_inputs: %{"role_id" => role_id},
        backend_label: "test",
        runtime_profile: :test,
        margins: %{agent: 1.0, role: 1.0}
      }
    end

    defp role_score(2), do: 10.0
    defp role_score(_), do: 1.0
  end

  defmodule ThinkerRuntime do
    @behaviour Trinity.Coordinator.ModelRuntime

    @impl true
    def load(_plan, _opts), do: {:ok, :loaded}

    @impl true
    def route(_state, _plan, _opts), do: {:ok, Runtime.route_logits(1)}
  end

  defmodule Caller do
    @behaviour Trinity.Coordinator.AgentCaller

    @impl true
    def call(%AgentCallIntent{role_ref: "worker"} = intent, _opts) do
      {:ok, receipt(intent, "Worker answer: 42")}
    end

    def call(%AgentCallIntent{role_ref: "thinker"} = intent, _opts) do
      {:ok,
       receipt(
         intent,
         """
         <suggestion>Ask the worker.</suggestion>
         <suggested_role>solver</suggested_role>
         """
       )}
    end

    def call(%AgentCallIntent{role_ref: "verifier"} = intent, _opts) do
      {:ok, receipt(intent, "ACCEPT: correct")}
    end

    defp receipt(intent, text) do
      %AgentCallReceipt{intent_ref: intent.intent_ref, status: :ok, metadata: %{text: text}}
    end
  end

  defmodule SlowCaller do
    @behaviour Trinity.Coordinator.AgentCaller

    @impl true
    def call(%AgentCallIntent{} = intent, _opts) do
      Process.sleep(25)

      {:ok,
       %AgentCallReceipt{
         intent_ref: intent.intent_ref,
         status: :ok,
         metadata: %{text: "Worker answer: slow"}
       }}
    end
  end

  defmodule MissingTextCaller do
    @behaviour Trinity.Coordinator.AgentCaller

    @impl true
    def call(%AgentCallIntent{} = intent, _opts) do
      {:ok, %AgentCallReceipt{intent_ref: intent.intent_ref, status: :ok, metadata: %{}}}
    end
  end

  defmodule TestTraceSink do
    @behaviour Trinity.Coordinator.TraceSink

    @impl true
    def emit(event, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:trace_event, event})
      :ok
    end
  end

  test "state manager normalizes and appends transcript messages" do
    {:ok, pid} = StateManager.start_link([%{"role" => "user", "content" => "hello"}])
    assert StateManager.get_messages(pid) == [%{role: "user", content: "hello"}]
    assert :ok = StateManager.append_assistant(pid, "answer")
    assert List.last(StateManager.get_messages(pid)) == %{role: "assistant", content: "answer"}
  end

  test "role injector preserves worker thinker verifier aliases and prompts" do
    assert RoleInjector.role_name("solver") == "Worker"
    assert RoleInjector.role_name(:thinker) == "Thinker"
    assert RoleInjector.role_id("v") == 2
    assert RoleInjector.role_atom("Worker") == :worker

    [system | _] = RoleInjector.inject_role([%{role: "user", content: "x"}], :verifier)
    assert system.role == "system"
    assert system.content =~ "ACCEPT or REVISE"
  end

  test "thinker and verifier parsers preserve loop control semantics" do
    thinker =
      Thinker.parse("""
      <suggestion>Compute it.</suggestion>
      <suggested_role>solver</suggested_role>
      """)

    assert thinker.suggested_role == "Worker"
    assert thinker.suggested_role_id == 0

    assert Verifier.parse(" revise - arithmetic error ").status == :revised
    assert Verifier.accepted?(:verifier, "ACCEPT: done")
    refute Verifier.accepted?(:worker, "ACCEPT: done")
    assert Verifier.safe_status(Verifier.parse("maybe")) == :revised
  end

  test "route decision derivation computes margins and trace-safe maps" do
    {:ok, decision} =
      RouteDecisionDerivation.from_route(
        %{agent_id: 0, role_id: 2, agent_logits: [1.0, 0.5], role_logits: [0.0, 0.1, 3.0]},
        [%{role: "user", content: "hello"}],
        router_artifact_ref: "artifact",
        extractor_ref: "extractor",
        head_ref: "head"
      )

    assert decision.selected_agent_id == 0
    assert decision.selected_role_id == 2
    assert decision.role_name == "Verifier"
    assert decision.margins.agent == 0.5
    assert decision.margins.role == 2.9

    assert decision.transcript_hash ==
             "f08a41138f0ae20bd9529ec45f6bccf323fd400841a625fae74682481abe83f3"

    trace = RouteDecisionDerivation.to_trace_map(decision)
    assert trace.agent_id == 0
    assert trace.role_name == "Verifier"
  end

  test "route decision derivation consumes Crucible policy decisions" do
    crucible_decision =
      CruciblePolicy.RouteDecision.new!(
        trace_id: "trace-crucible",
        decision_id: "crucible-decision-2",
        selected_target: :verifier,
        selected_model: :fixture_model,
        confidence: 0.58,
        uncertainty: %CruciblePolicy.Uncertainty{entropy: 3.0},
        evidence_refs: ["final_logits"]
      )

    assert {:ok, decision} =
             RouteDecisionDerivation.from_crucible(
               crucible_decision,
               [%{role: "user", content: "check"}],
               selected_agent_id: 3
             )

    assert decision.selected_agent_id == 3
    assert decision.selected_role_id == 2
    assert decision.role_name == "Verifier"
    assert decision.trace_ref == "trace-crucible"
    assert decision.backend_label == :crucible_policy
    assert decision.metadata.crucible_evidence_refs == ["final_logits"]
  end

  test "governed authority materializes provider options and rejects direct bypasses" do
    authority = [
      authority_ref: "auth",
      workflow_ref: "workflow",
      runtime_ref: "runtime",
      credential_ref: "credential",
      api_key: "secret",
      provider_pool: [%{provider: :test, model: "mock"}]
    ]

    assert {:ok, opts} =
             RunGovernance.materialize_orchestrator_opts(governed_authority: authority)

    assert opts[:governed_authority_ref] == "auth"
    assert opts[:agent_pool_opts][:api_key] == "secret"
    assert opts[:trace][:redaction_values] == ["secret"]

    assert {:error, {:governed_direct_fields_rejected, [:provider_pool]}} =
             RunGovernance.materialize_orchestrator_opts(
               governed_authority: authority,
               provider_pool: :direct
             )
  end

  test "budget keys and counters preserve coordinator halt semantics" do
    assert Budgets.keys() == [
             :max_wall_time_ms,
             :max_provider_calls,
             :max_provider_latency_ms,
             :max_verifier_revisions,
             :max_estimated_cost_usd,
             :cost_estimator_fn
           ]

    ctx = Budgets.new_context(max_provider_calls: 1)
    assert :ok = Budgets.bump_provider_call(ctx)
    assert {:budget_exceeded, :provider_calls, details} = Budgets.bump_provider_call(ctx)
    assert details.limit == 1
    assert details.observed == 2

    cost_ctx =
      Budgets.new_context(max_estimated_cost_usd: 0.01, cost_estimator_fn: fn _ -> 0.02 end)

    assert :ok = Budgets.bump_estimated_cost(cost_ctx, %{})

    assert {:budget_exceeded, :estimated_cost_usd, cost_details} =
             Budgets.check(cost_ctx, :after_dispatch)

    assert cost_details.observed_usd == 0.02
  end

  test "orchestrator runs worker then verifier through behaviours" do
    assert {:ok, result} =
             Orchestrator.run_loop([%{role: "user", content: "solve"}],
               model_runtime: Runtime,
               model_state: :loaded,
               agent_caller: Caller,
               max_turns: 3
             )

    assert result.response == "ACCEPT: correct"
    assert Enum.map(result.messages, & &1.role) == ["user", "assistant", "assistant"]
  end

  test "orchestrator emits fitness-bearing lifecycle events" do
    assert {:ok, _result} =
             Orchestrator.run_loop([%{role: "user", content: "solve"}],
               model_runtime: Runtime,
               model_state: :loaded,
               agent_caller: Caller,
               max_turns: 3,
               coordination_run_ref: "run:trace",
               trace_ref: "trace:trace",
               runtime_profile: :mock_tiny,
               provider_pool: "mock",
               route_path: :orchestrator,
               trace_sink: TestTraceSink,
               trace: [test_pid: self()]
             )

    events = collect_trace_events([])
    event_types = Enum.map(events, & &1.event_type)

    assert :route_decision in event_types
    assert :provider_dispatch_started in event_types
    assert :provider_dispatch_finished in event_types
    assert :verifier_result in event_types
    assert :budget_snapshot in event_types
    assert :run_finished in event_types

    route = Enum.find(events, &(&1.event_type == :route_decision))
    assert route.coordination_run_ref == "run:trace"
    assert route.payload.runtime_profile == :test
    assert route.payload.provider_pool == "mock"
    assert route.payload.route_path == :orchestrator
    assert route.payload.selected_agent_id == 0
    assert route.payload.selected_role_id == 0
    assert route.payload.min_margin == 1.0

    finished = Enum.find(events, &(&1.event_type == :provider_dispatch_finished))
    assert finished.payload.ok == true
    assert is_integer(finished.payload.latency_ms)
    refute Map.has_key?(finished.payload, :text)

    verifier = Enum.find(events, &(&1.event_type == :verifier_result))
    assert verifier.payload.status == :accepted
    assert verifier.payload.safe_status == :accepted
    assert is_binary(verifier.payload.verifier_response_ref)

    run_finished = Enum.find(events, &(&1.event_type == :run_finished))
    assert run_finished.payload.status == :finished
    assert run_finished.payload.provider_calls == 2
    assert run_finished.payload.verifier_revisions == 0
  end

  test "orchestrator emits run_failed with budget counters" do
    assert {:error, {:budget_exceeded, :provider_calls, _details}} =
             Orchestrator.run_loop([%{role: "user", content: "loop"}],
               model_runtime: Runtime,
               model_state: :loaded,
               agent_caller: Caller,
               max_turns: 5,
               max_provider_calls: 1,
               coordination_run_ref: "run:failed",
               trace_sink: TestTraceSink,
               trace: [test_pid: self()]
             )

    events = collect_trace_events([])
    failed = Enum.find(events, &(&1.event_type == :run_failed))
    assert failed.payload.status == :failed
    assert failed.payload.provider_calls == 2
    assert failed.payload.budget_exceeded_key == :provider_calls
    refute Map.has_key?(failed.payload, :reason)
  end

  test "orchestrator closes a dispatch span when a receipt has no response text" do
    assert {:error, :missing_agent_response_text} =
             Orchestrator.run_loop([%{role: "user", content: "solve"}],
               model_runtime: Runtime,
               model_state: :loaded,
               agent_caller: MissingTextCaller,
               max_turns: 1,
               coordination_run_ref: "run:missing-text",
               trace_sink: TestTraceSink,
               trace: [test_pid: self()]
             )

    events = collect_trace_events([])
    started = Enum.find(events, &(&1.event_type == :provider_dispatch_started))
    finished = Enum.find(events, &(&1.event_type == :provider_dispatch_finished))

    assert finished.payload.dispatch_ref == started.payload.dispatch_ref
    assert finished.payload.ok == false
    assert is_binary(finished.payload.error_ref)
    assert Enum.any?(events, &(&1.event_type == :run_failed))
  end

  test "orchestrator consumes Crucible policy route decisions" do
    assert {:ok, result} =
             Orchestrator.run_loop([%{role: "user", content: "solve"}],
               model_runtime: CrucibleRuntime,
               model_state: :loaded,
               extraction_plan:
                 CrucibleTap.TapPlan.new!([[id: "logits", signal_type: :final_logits]]),
               agent_caller: Caller,
               max_turns: 1
             )

    assert result.response == "Worker answer: 42"
  end

  test "orchestrator applies thinker role suggestions through behaviour state" do
    assert {:ok, result} =
             Orchestrator.run_loop([%{role: "user", content: "plan"}],
               model_runtime: ThinkerRuntime,
               model_state: :loaded,
               agent_caller: Caller,
               max_turns: 2
             )

    assert result.response == "Worker answer: 42"
  end

  test "orchestrator enforces provider call and latency budgets" do
    assert {:error, {:budget_exceeded, :provider_calls, details}} =
             Orchestrator.run_loop([%{role: "user", content: "loop"}],
               model_runtime: Runtime,
               model_state: :loaded,
               agent_caller: Caller,
               max_turns: 5,
               max_provider_calls: 1
             )

    assert details.observed == 2

    assert {:error, {:budget_exceeded, :provider_latency_ms, latency}} =
             Orchestrator.run_loop([%{role: "user", content: "slow"}],
               model_runtime: Runtime,
               model_state: :loaded,
               agent_caller: SlowCaller,
               max_turns: 1,
               max_provider_latency_ms: 1
             )

    assert latency.observed_ms >= 1
  end

  defp collect_trace_events(acc) do
    receive do
      {:trace_event, event} -> collect_trace_events([event | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
