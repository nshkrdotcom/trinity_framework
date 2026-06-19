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

  test "TraceAdapter keeps Qwen artifact identity separate from backend identity" do
    logits = %{
      logits_fixture()
      | backend_label: "EXLA.Backend<cuda:0>",
        runtime_profile: :cuda_exla
    }

    runtime_profile = %{
      name: :cuda_exla,
      adapter_id: :trinity_qwen3_0_6b_sakana,
      model_id: "Qwen/Qwen3-0.6B",
      artifact_ref: "artifact:qwen3-0.6b-sakana",
      artifact_repo: "nshkrdotcom/trinity-coordinator-adapted-qwen3-0.6b",
      artifact_revision: "v1.0.0",
      artifact_manifest_sha256: String.duplicate("a", 64),
      artifact_manifest_sha256_actual: String.duplicate("a", 64),
      artifact_pin_manifest_sha256: String.duplicate("a", 64),
      artifact_pin_verified?: true,
      artifact_manifest_path: "/tmp/trinity/artifact/manifest.json",
      artifact_pin_path: "/tmp/trinity/artifact/artifact_pin.json",
      artifact_root: "/tmp/trinity/artifact",
      artifact_status: :available,
      artifact_available?: true,
      qwen_base_model?: true,
      sakana_route_artifact?: true,
      runtime_loaded?: true,
      executed_runtime?: true,
      qwen_loaded?: true,
      router_head_shape: [10, 1024],
      selected_tensor_count: 9,
      scale_offset_count: 9216,
      source_vector_shape: [19_456]
    }

    context =
      RequestContext.from_messages([%{"role" => "user", "content" => "Route with CUDA."}],
        runtime_profile: runtime_profile
      )

    {:ok, tap_plan} = TapPlanBuilder.build(context, runtime_profile)

    trace = TraceAdapter.from_logits(logits, context, tap_plan, trace_id: "trace:qwen")

    assert trace.model_id == "Qwen/Qwen3-0.6B"
    assert trace.backend == :exla_cuda
    assert trace.final_logits.backend == :exla_cuda
    assert trace.metadata.model_id == "Qwen/Qwen3-0.6B"
    assert trace.metadata.backend_label == "EXLA.Backend<cuda:0>"
    assert trace.metadata.runtime_profile == "cuda_exla"
    assert trace.metadata.adapter_id == :trinity_qwen3_0_6b_sakana
    assert trace.metadata.artifact_ref == "artifact:qwen3-0.6b-sakana"
    assert trace.metadata.artifact_repo == "nshkrdotcom/trinity-coordinator-adapted-qwen3-0.6b"
    assert trace.metadata.artifact_status == :available
    assert trace.metadata.artifact_manifest_sha256_actual == String.duplicate("a", 64)
    assert trace.metadata.artifact_pin_manifest_sha256 == String.duplicate("a", 64)
    assert trace.metadata.artifact_pin_verified? == true
    refute Map.has_key?(trace.metadata, :artifact_manifest_path)
    refute Map.has_key?(trace.metadata, :artifact_pin_path)
    refute Map.has_key?(trace.metadata, :artifact_root)
    assert trace.metadata.local_artifact_manifest_path == "/tmp/trinity/artifact/manifest.json"
    assert trace.metadata.local_artifact_pin_path == "/tmp/trinity/artifact/artifact_pin.json"
    assert trace.metadata.local_artifact_root == "/tmp/trinity/artifact"
    assert trace.metadata.artifact_available? == true
    assert trace.metadata.qwen_base_model? == true
    assert trace.metadata.sakana_route_artifact? == true
    assert trace.metadata.runtime_loaded? == true
    assert trace.metadata.executed_runtime? == true
    assert trace.metadata.qwen_loaded? == true
    assert trace.metadata.router_head_shape == [10, 1024]
    assert trace.metadata.selected_tensor_count == 9
    assert trace.metadata.scale_offset_count == 9216
    assert trace.metadata.source_vector_shape == [19_456]
    assert trace.final_logits.metadata.artifact_ref == "artifact:qwen3-0.6b-sakana"
    assert trace.final_logits.metadata.artifact_status == :available
    assert trace.final_logits.metadata.artifact_pin_verified? == true
    assert trace.final_logits.metadata.executed_runtime? == true
    refute Map.has_key?(trace.final_logits.metadata, :artifact_manifest_path)
    refute Map.has_key?(trace.final_logits.metadata, :artifact_pin_path)

    assert trace.final_logits.metadata.local_artifact_manifest_path ==
             "/tmp/trinity/artifact/manifest.json"
  end

  test "TraceAdapter does not atomize arbitrary backend labels" do
    backend_label = "custom backend label 1234 !"
    logits = %{logits_fixture() | backend_label: backend_label, runtime_profile: :custom}
    context = RequestContext.from_messages([%{"role" => "user", "content" => "Route custom."}])
    {:ok, tap_plan} = TapPlanBuilder.build(context, %{name: :custom})

    trace = TraceAdapter.from_logits(logits, context, tap_plan, trace_id: "trace:custom-backend")

    assert trace.backend == :route_logits
    assert trace.final_logits.backend == :route_logits
    assert trace.metadata.backend_label == backend_label
    assert trace.final_logits.metadata.backend_label == backend_label
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

  test "DecisionAdapter sanitizer keeps stable collapsed policy refs" do
    cases = [
      {"abc", "abc"},
      {"a b", "a_b"},
      {"a///b", "a_b"},
      {"é/🔥", "_"},
      {"../../path", ".._.._path"},
      {"", ""}
    ]

    for {policy_ref, expected} <- cases do
      crucible =
        CrucibleRouteDecision.new!(
          decision_id: "decision:sanitize",
          trace_id: "trace:sanitize",
          policy_ref: policy_ref,
          selected_target: :worker,
          selected_model: "model:test",
          confidence: 0.9,
          uncertainty: %CruciblePolicy.Uncertainty{},
          evidence_refs: []
        )

      assert {:ok, %RouteDecision{} = decision} =
               DecisionAdapter.adapt(crucible, coordination_run_ref: "run:sanitize")

      assert decision.router_artifact_ref == "crucible_policy:#{expected}"
      assert decision.head_ref == "crucible_policy_plan:#{expected}"
    end
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
