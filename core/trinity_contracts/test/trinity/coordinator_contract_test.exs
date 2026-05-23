defmodule Trinity.CoordinatorContractTest do
  use ExUnit.Case, async: true

  alias Trinity.Coordinator.{
    AdapterRef,
    AgentCallIntent,
    AgentCallReceipt,
    ArtifactRef,
    HiddenStateExtractionPlan,
    RouteDecision,
    RouteLogits,
    RuntimeProfileRef,
    TraceEvent
  }

  defmodule TestModelRuntime do
    @behaviour Trinity.Coordinator.ModelRuntime

    @impl true
    def load(%HiddenStateExtractionPlan{} = plan, _opts), do: {:ok, %{plan: plan}}

    @impl true
    def route(_runtime, %HiddenStateExtractionPlan{} = _plan, _opts), do: {:ok, route_logits()}

    defp route_logits do
      %RouteLogits{
        role_logits: [0.1, 0.2, 0.9],
        agent_logits: [0.1, 0.7],
        selected_role_id: 2,
        selected_agent_id: 1,
        token_count: 17,
        transcript_hash: "sha256:transcript",
        route_hash_inputs: %{"agent_id" => 1, "role_id" => 2},
        backend_label: :mock,
        runtime_profile: :mock_tiny,
        margins: %{agent: 0.6, role: 0.7}
      }
    end
  end

  defmodule TestRouterRuntime do
    @behaviour Trinity.Coordinator.RouterRuntime

    @impl true
    def decide(%RouteLogits{} = logits, opts), do: RouteDecision.from_logits(logits, opts)
  end

  defmodule TestAgentCaller do
    @behaviour Trinity.Coordinator.AgentCaller

    @impl true
    def call(%AgentCallIntent{} = intent, _opts) do
      {:ok,
       %AgentCallReceipt{intent_ref: intent.intent_ref, status: :ok, response_ref: "response/ref"}}
    end
  end

  defmodule TestTraceSink do
    @behaviour Trinity.Coordinator.TraceSink

    @impl true
    def emit(%TraceEvent{}, _opts), do: :ok
  end

  defmodule TestArtifactResolver do
    @behaviour Trinity.Coordinator.ArtifactResolver

    @impl true
    def resolve(%ArtifactRef{} = artifact_ref, _opts), do: {:ok, artifact_ref}
  end

  test "adapter refs keep typed stable keys without dynamic atom conversion" do
    assert {:ok, adapter_ref} =
             AdapterRef.new(
               id: :trinity_qwen3_0_6b_sakana,
               version: "0.1.0",
               contract: :route_logits_v1
             )

    assert AdapterRef.key(adapter_ref) ==
             {:trinity_qwen3_0_6b_sakana, "0.1.0", :route_logits_v1}

    assert {:error, {:invalid_atom_field, :id, "trinity_qwen3_0_6b_sakana"}} =
             AdapterRef.new(%{
               "id" => "trinity_qwen3_0_6b_sakana",
               "version" => "0.1.0",
               "contract" => :route_logits_v1
             })
  end

  test "runtime route decisions project every public ref field unchanged" do
    logits = route_logits()

    attrs = %{
      router_decision_ref: "router_decision/run/1",
      coordination_run_ref: "run/1",
      router_artifact_ref: "router/artifact",
      extractor_ref: "extractor/qwen",
      head_ref: "head/sakana",
      selected_role_ref: "role/verifier",
      confidence_band: :high,
      fallback_reason: nil,
      trace_ref: "trace/1",
      replay_ref: "replay/1",
      route_hash: "sha256:route"
    }

    assert {:ok, decision} = RouteDecision.from_logits(logits, attrs)

    public = RouteDecision.to_router_decision(decision)
    projection = Trinity.RouterDecision.to_projection(public)

    for key <- [
          :router_decision_ref,
          :coordination_run_ref,
          :router_artifact_ref,
          :extractor_ref,
          :head_ref,
          :selected_role_ref,
          :confidence_band,
          :fallback_reason,
          :trace_ref,
          :replay_ref
        ] do
      assert Map.fetch!(projection, key) == Map.fetch!(attrs, key)
    end

    assert decision.selected_agent_id == 1
    assert decision.selected_role_id == 2
    assert decision.route_hash_inputs == %{"agent_id" => 1, "role_id" => 2}
  end

  test "coordinator behaviours accept dependency-free DTOs" do
    adapter_ref = AdapterRef.new!(id: :mock_tiny, version: "0.1.0", contract: :route_logits_v1)

    plan = %HiddenStateExtractionPlan{
      adapter_ref: adapter_ref,
      runtime_profile_ref: %RuntimeProfileRef{name: :mock_tiny},
      messages: [%{role: "user", content: "route me"}]
    }

    assert {:ok, runtime} = TestModelRuntime.load(plan, [])
    assert {:ok, %RouteLogits{} = logits} = TestModelRuntime.route(runtime, plan, [])

    assert {:ok, %RouteDecision{} = decision} =
             TestRouterRuntime.decide(logits,
               router_decision_ref: "router_decision/run/2",
               coordination_run_ref: "run/2",
               router_artifact_ref: "router/artifact",
               extractor_ref: "extractor/qwen",
               head_ref: "head/sakana",
               selected_role_ref: "role/verifier",
               confidence_band: :high
             )

    intent = %AgentCallIntent{
      intent_ref: "intent/1",
      role_ref: decision.selected_role_ref,
      messages: []
    }

    assert {:ok, %AgentCallReceipt{status: :ok}} = TestAgentCaller.call(intent, [])
    assert :ok = TestTraceSink.emit(%TraceEvent{event_ref: "event/1", event_type: :route}, [])

    artifact_ref = %ArtifactRef{artifact_ref: "artifact/qwen", sha256: "sha256:artifact"}
    assert {:ok, ^artifact_ref} = TestArtifactResolver.resolve(artifact_ref, [])
  end

  defp route_logits do
    %RouteLogits{
      role_logits: [0.1, 0.2, 0.9],
      agent_logits: [0.1, 0.7],
      selected_role_id: 2,
      selected_agent_id: 1,
      token_count: 17,
      transcript_hash: "sha256:transcript",
      route_hash_inputs: %{"agent_id" => 1, "role_id" => 2},
      backend_label: :mock,
      runtime_profile: :mock_tiny,
      margins: %{agent: 0.6, role: 0.7}
    }
  end
end
