defmodule TrinityFramework.Integration.TraceAdapterTest do
  use ExUnit.Case, async: true

  alias CruciblePolicy.RouteDecision, as: CrucibleRouteDecision
  alias Trinity.Coordinator.{RouteDecision, RouteLogits}
  alias Trinity.Crucible.{DecisionAdapter, RequestContext, TapPlanBuilder, TraceAdapter}

  test "TraceAdapter builds bounded Crucible traces from route logits" do
    logits = logits_fixture()
    context = RequestContext.from_messages([%{"role" => "user", "content" => "Verify this."}])
    {:ok, tap_plan} = TapPlanBuilder.build(context, %{name: :mock_tiny})

    trace = TraceAdapter.from_logits(logits, context, tap_plan, trace_id: "trace:test")

    assert trace.trace_id == "trace:test"
    assert trace.tap_plan_ref == tap_plan.plan_id
    assert [record] = trace.signals
    assert record.signal_type == :final_logits
    assert record.tensor_summary.entropy > 0.0

    assert {:ok, [_ | _]} =
             CrucibleSignalTrace.LayerTrajectory.cosine_drifts(trace.layer_trajectory)
  end

  test "DecisionAdapter maps Crucible policy decisions to deterministic Trinity route decisions" do
    crucible =
      CrucibleRouteDecision.new!(
        decision_id: "decision:test",
        trace_id: "trace:test",
        policy_ref: "policy:test",
        selected_target: :verifier,
        selected_model: "model:test",
        confidence: 0.91,
        uncertainty: %CruciblePolicy.Uncertainty{entropy: 0.2},
        evidence_refs: ["signal:final"],
        metadata: %{selected_agent_id: 6}
      )

    assert {:ok, %RouteDecision{} = decision} =
             DecisionAdapter.adapt(crucible,
               coordination_run_ref: "run:test",
               messages_or_hash: "hash:test"
             )

    assert decision.router_decision_ref == "decision:test"
    assert decision.coordination_run_ref == "run:test"
    assert decision.router_artifact_ref == "crucible_policy:policy:test"
    assert decision.extractor_ref == "crucible_trace:trace:test"
    assert decision.head_ref == "crucible_policy_plan:policy:test"
    assert decision.selected_role_ref == "role:verifier"
    assert decision.selected_role_id == 2
    assert decision.selected_agent_id == 6
    assert decision.confidence_band == :high
  end

  defp logits_fixture do
    %RouteLogits{
      role_logits: [0.1, 0.2, 1.0],
      agent_logits: [0.0, 0.2, 0.1, 0.3, 0.9, 0.4, 0.5],
      selected_role_id: 2,
      selected_agent_id: 4,
      token_count: 4,
      transcript_hash: "hash:test",
      route_hash_inputs: %{"fixture" => true},
      backend_label: :mock_tiny,
      runtime_profile: :mock_tiny,
      margins: %{role: 0.8, agent: 0.4}
    }
  end
end
