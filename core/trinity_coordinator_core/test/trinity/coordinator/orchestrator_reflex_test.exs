defmodule Trinity.Coordinator.OrchestratorReflexTest do
  use ExUnit.Case, async: true

  alias Trinity.Coordinator.{AgentCallIntent, AgentCallReceipt, Orchestrator, RouteLogits}

  defmodule Runtime do
    @behaviour Trinity.Coordinator.ModelRuntime

    @impl true
    def load(_plan, _opts), do: {:ok, :loaded}

    @impl true
    def route(state, _plan, opts) do
      turn = Keyword.fetch!(opts, :turn)

      {:ok,
       %RouteLogits{
         role_logits: [0.0, 0.0, 0.0],
         agent_logits: [0.0, 0.0],
         selected_role_id: state.role_id,
         selected_agent_id: 0,
         token_count: 4,
         transcript_hash: String.duplicate("a", 64),
         route_hash_inputs: %{turn: turn, role_id: state.role_id},
         backend_label: "reflex-test",
         runtime_profile: :mock_tiny,
         margins: state.margins
       }}
    end
  end

  defmodule Caller do
    @behaviour Trinity.Coordinator.AgentCaller

    @impl true
    def call(%AgentCallIntent{} = intent, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:intent, intent.role_ref})

      text =
        case intent.role_ref do
          "thinker" ->
            "<suggestion>Check carefully.</suggestion><suggested_role>solver</suggested_role>"

          "verifier" ->
            Keyword.get(opts, :verifier_text, "ACCEPT: reflex verified")

          "worker" ->
            "Worker answer: direct"
        end

      {:ok,
       %AgentCallReceipt{
         intent_ref: intent.intent_ref,
         response_ref: "response:#{intent.role_ref}",
         status: :ok,
         metadata: %{text: text, provider: :mock, model: "mock-reflex"}
       }}
    end
  end

  defmodule TraceSink do
    @behaviour Trinity.Coordinator.TraceSink

    @impl true
    def emit(event, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:trace_event, event})
      :ok
    end
  end

  test "high and medium confidence dispatch selected roles and emit bounded decisions" do
    assert {:ok, _result} = run(0, %{agent: 3.0, role: 3.0}, max_turns: 1)
    assert collect_intents() == ["worker"]

    high = collect_events() |> event!(:reflex_decision)
    assert high.payload.confidence_class == :high
    assert high.payload.action == :direct_dispatch
    assert high.payload.original_role_atom == :worker

    assert {:ok, _result} = run(0, %{agent: 1.5, role: 1.5}, max_turns: 1)
    assert collect_intents() == ["worker"]

    medium = collect_events() |> event!(:reflex_decision)
    assert medium.payload.confidence_class == :medium
    assert medium.payload.action == :normal_dispatch
  end

  test "low-confidence worker forces Thinker then Verifier without Worker dispatch" do
    assert {:ok, result} = run(0, %{agent: 0.5, role: 0.5}, max_turns: 2)
    assert result.response == "ACCEPT: reflex verified"
    assert collect_intents() == ["thinker", "verifier"]

    events = collect_events()

    dispatch_roles =
      events
      |> Enum.filter(&(&1.event_type == :provider_dispatch_started))
      |> Enum.map(& &1.payload.selected_role_id)

    assert dispatch_roles == [1, 2]

    reflex = event!(events, :reflex_decision)
    assert reflex.payload.original_role_atom == :worker
    assert reflex.payload.action == :thinker_then_verifier
    assert reflex.payload.forced_sequence == [:thinker, :verifier]
    assert reflex.payload.next_role_override == 1
  end

  test "low-confidence Thinker dispatches Thinker and forces Verifier next" do
    assert {:ok, _result} = run(1, %{agent: 0.5, role: 0.5}, max_turns: 2)
    assert collect_intents() == ["thinker", "verifier"]

    reflex = collect_events() |> event!(:reflex_decision)
    assert reflex.payload.original_role_atom == :thinker
    assert reflex.payload.next_role_override == 2
  end

  test "low-confidence Verifier dispatches directly and can verify without Worker" do
    assert {:ok, result} = run(2, %{agent: 0.5, role: 0.5}, max_turns: 1)
    assert result.response == "ACCEPT: reflex verified"
    assert collect_intents() == ["verifier"]

    events = collect_events()
    assert event!(events, :verifier_result).payload.status == :accepted
    assert event!(events, :run_finished).payload.status == :finished
  end

  test "Verifier revise preserves revision budgets and terminal failure traces" do
    assert {:error, :max_turns_reached} =
             run(0, %{agent: 0.5, role: 0.5},
               max_turns: 2,
               verifier_text: "REVISE: insufficient evidence"
             )

    assert collect_intents() == ["thinker", "verifier"]
    events = collect_events()
    verifier = event!(events, :verifier_result)

    revision_budget =
      Enum.find(events, fn event ->
        event.event_type == :budget_snapshot and
          event.payload.checkpoint == :after_verifier_revision
      end)

    assert verifier.payload.status == :revise
    assert verifier.payload.revision_count == 1
    assert revision_budget.payload.verifier_revisions == 1
    assert event!(events, :run_failed).payload.status == :failed
  end

  test "reflex disabled preserves selected-role dispatch and records disabled state" do
    assert {:ok, _result} =
             run(0, %{agent: 0.0, role: 0.0}, max_turns: 1, reflex_enabled?: false)

    assert collect_intents() == ["worker"]
    reflex = collect_events() |> event!(:reflex_decision)
    assert reflex.payload.reflex_enabled == false
    assert reflex.payload.action == :normal_dispatch
    assert reflex.payload.reason == :disabled
  end

  test "trace ordering and payload remain fitness-compatible and secret-free" do
    assert {:ok, _result} = run(0, %{agent: 3.0, role: 3.0}, max_turns: 1)
    _intents = collect_intents()
    events = collect_events()
    types = Enum.map(events, & &1.event_type)

    assert Enum.take(types, 3) == [:route_decision, :reflex_decision, :budget_snapshot]
    assert :provider_dispatch_started in types
    assert :provider_dispatch_finished in types
    assert :run_finished in types

    reflex = event!(events, :reflex_decision)
    encoded = inspect(reflex.payload)
    refute String.contains?(encoded, "classified prompt secret")
    refute String.contains?(encoded, "authorization")
    refute Map.has_key?(reflex.payload, :messages)
    refute Map.has_key?(reflex.payload, :provider_payload)

    finished = event!(events, :provider_dispatch_finished)
    assert is_integer(finished.payload.latency_ms)
  end

  defp run(role_id, margins, opts) do
    {verifier_text, opts} = Keyword.pop(opts, :verifier_text, "ACCEPT: reflex verified")

    Orchestrator.run_loop([%{role: "user", content: "classified prompt secret"}],
      model_runtime: Runtime,
      model_state: %{role_id: role_id, margins: margins},
      agent_caller: Caller,
      agent_opts: [test_pid: self(), verifier_text: verifier_text],
      max_turns: Keyword.fetch!(opts, :max_turns),
      reflex_enabled?: Keyword.get(opts, :reflex_enabled?, true),
      reflex_margin_mode: :absolute,
      reflex_high_agent_margin: 2.0,
      reflex_high_role_margin: 2.0,
      reflex_low_agent_margin: 1.0,
      reflex_low_role_margin: 1.0,
      coordination_run_ref: "run:reflex-test",
      trace_ref: "trace:reflex-test",
      trace_sink: TraceSink,
      trace: [test_pid: self()]
    )
  end

  defp collect_intents(acc \\ []) do
    receive do
      {:intent, role} -> collect_intents([role | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp collect_events(acc \\ []) do
    receive do
      {:trace_event, event} -> collect_events([event | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp event!(events, type),
    do: Enum.find(events, &(&1.event_type == type)) || flunk("missing #{type}")
end
