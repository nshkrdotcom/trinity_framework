defmodule Trinity.MezzanineRouterAdapterTest do
  use ExUnit.Case, async: true

  alias OuterBrain.ContextABI.Failure
  alias Trinity.MezzanineRouterAdapter

  test "routes Mezzanine route requests through TRINITY and returns Mezzanine decision shape" do
    request = route_request()

    assert {:ok, decision} =
             MezzanineRouterAdapter.route(request,
               trinity_config: trinity_config(),
               preferred_role_ref: "role://fixture/worker"
             )

    assert decision.route_decision_ref ==
             "router_decision:workflow://router-fabric/demo:role://fixture/worker"

    assert decision.context_packet_ref == request.context_packet_ref
    assert decision.packet_hash == request.packet_hash
    assert decision.selected_route_kind == :trinity_coordinated
    assert decision.selected_model_profile_ref == "model-profile://fixture/worker"
    assert decision.provider_or_runtime_ref == "runtime://fixture/worker"
    assert decision.provider_family == "mock"
    assert decision.route_policy_ref == request.route_policy_ref
    assert decision.verifier_ref == "verifier-profile://fixture/worker"
    assert decision.authority_packet_ref == request.authority_ref
    assert decision.trace_ref == request.trace_ref
    assert decision.reason_codes == ["trinity.route.selected.v1"]
    assert decision.trinity.selected_role_ref == "role://fixture/worker"
  end

  test "uses a ref-only default TRINITY config when caller does not provide one" do
    assert {:ok, decision} = MezzanineRouterAdapter.route(route_request())

    assert decision.selected_route_kind == :trinity_coordinated
    assert decision.selected_model_profile_ref == "model-profile://fixture/worker"
    assert decision.provider_family == "mock"
    assert decision.reason_codes == ["trinity.route.default_role.v1"]
  end

  test "rejects raw route request payloads with owner-local failure" do
    request = Map.put(route_request(), :raw_prompt, "do not carry me")

    assert {:error, %Failure{} = failure} = MezzanineRouterAdapter.route(request)
    assert failure.owner == :trinity
    assert failure.reason_code == "trinity.route.raw_payload_rejected.v1"
    assert failure.safe_message == "route request cannot carry raw payloads"
    assert "field://raw_prompt" in failure.evidence_refs
  end

  defp route_request do
    %{
      tenant_ref: "tenant://router-fabric/demo",
      workflow_ref: "workflow://router-fabric/demo",
      context_packet_ref: "context-packet://router-fabric/demo",
      packet_hash: "sha256:#{String.duplicate("a", 64)}",
      authority_ref: "authority://router-fabric/demo",
      route_policy_ref: "route-policy://router-fabric/demo",
      model_class_allowlist: ["model-profile://fixture/worker"],
      trace_ref: "trace://router-fabric/demo"
    }
  end

  defp trinity_config do
    %{
      router_artifact: %{
        router_artifact_ref: "router-artifact://fixture/router",
        extractor_ref: "extractor://fixture/context",
        head_ref: "head://fixture/router",
        compatibility_ref: "compatibility://fixture/router",
        calibration_ref: "calibration://fixture/router",
        parity_ref: "parity://fixture/router",
        hash_ref: "sha256:router"
      },
      role_packs: [
        %{
          role_ref: "role://fixture/worker",
          prompt_ref: "prompt://fixture/worker",
          capability_refs: ["capability://fixture/answer"],
          allowed_model_profile_refs: ["model-profile://fixture/worker"],
          tool_policy_ref: "tool-policy://fixture/none",
          memory_profile_ref: "memory-profile://fixture/ref-only",
          guardrail_profile_ref: "guardrail-profile://fixture/default",
          verifier_profile_ref: "verifier-profile://fixture/worker",
          budget_ref: "budget://fixture/worker",
          context_budget_ref: "context-budget://fixture/worker",
          handoff_policy_ref: "handoff-policy://fixture/worker",
          projection_ref: "projection://fixture/worker",
          gepa_target_refs: []
        }
      ],
      provider_pool: [
        %{
          slot_ref: "slot://fixture/worker",
          slot_kind: :mock,
          role_refs: ["role://fixture/worker"],
          model_profile_ref: "model-profile://fixture/worker",
          endpoint_profile_ref: "endpoint-profile://fixture/worker",
          operation_policy_ref: "operation-policy://fixture/worker",
          target_ref: "runtime://fixture/worker",
          credential_ref: "credential://fixture/ref-only",
          per_role_constraints: %{}
        }
      ]
    }
  end
end
