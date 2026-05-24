defmodule Trinity.RouterContractTest do
  use ExUnit.Case, async: true

  test "routes through extractor, head, artifact, decision, fallback, trace, and replay refs" do
    config =
      Trinity.Config.compile!(%{
        router_artifact: %{
          router_artifact_ref: "router/mock",
          extractor_ref: "extractor/mock",
          head_ref: "head/mock",
          compatibility_ref: "compat/qwen",
          calibration_ref: "calibration/golden",
          parity_ref: "parity/qwen-sakana",
          hash_ref: "sha256:router"
        },
        role_packs: [
          %{
            role_ref: "role/worker",
            prompt_ref: "prompt/worker",
            capability_refs: ["cap/code"],
            allowed_model_profile_refs: ["model/mock/worker"],
            tool_policy_ref: "tool/policy/worker",
            memory_profile_ref: "memory/role/worker",
            guardrail_profile_ref: "guardrail/role/worker",
            verifier_profile_ref: "verifier/role/worker",
            budget_ref: "budget/role/worker",
            context_budget_ref: "context/role/worker",
            handoff_policy_ref: "handoff/role/worker",
            projection_ref: "projection/role/worker",
            gepa_target_refs: ["gepa/target/role_prompt"]
          }
        ],
        provider_pool: [
          %{
            slot_ref: "slot/mock/worker",
            slot_kind: :mock,
            role_refs: ["role/worker"],
            model_profile_ref: "model/mock/worker",
            endpoint_profile_ref: "endpoint/mock/worker",
            operation_policy_ref: "policy/route/mock",
            target_ref: "target/mock/worker",
            credential_ref: "credential/mock/ref"
          }
        ]
      })

    assert {:ok, decision} =
             Trinity.Router.route(config, %{
               coordination_run_ref: "ai_run/coordination/1",
               preferred_role_ref: "role/worker",
               trace_ref: "trace/router/1",
               replay_ref: "replay/router/1"
             })

    assert decision.router_decision_ref == "router_decision:ai_run/coordination/1:role/worker"
    assert decision.router_artifact_ref == "router/mock"
    assert decision.extractor_ref == "extractor/mock"
    assert decision.head_ref == "head/mock"
    assert decision.selected_role_ref == "role/worker"
    assert decision.confidence_band == :high
    assert decision.fallback_reason == nil
    assert decision.trace_ref == "trace/router/1"
    assert decision.replay_ref == "replay/router/1"
  end

  test "invalid route falls back to the first role without raw payload projection" do
    config =
      Trinity.Config.compile!(%{
        router_artifact: %{
          router_artifact_ref: "router/mock",
          extractor_ref: "extractor/mock",
          head_ref: "head/mock",
          compatibility_ref: "compat/qwen",
          hash_ref: "sha256:router"
        },
        role_packs: [
          %{
            role_ref: "role/worker",
            prompt_ref: "prompt/worker",
            capability_refs: ["cap/code"],
            allowed_model_profile_refs: ["model/mock/worker"],
            tool_policy_ref: "tool/policy/worker",
            memory_profile_ref: "memory/role/worker",
            guardrail_profile_ref: "guardrail/role/worker",
            verifier_profile_ref: "verifier/role/worker",
            budget_ref: "budget/role/worker",
            context_budget_ref: "context/role/worker",
            handoff_policy_ref: "handoff/role/worker",
            projection_ref: "projection/role/worker",
            gepa_target_refs: ["gepa/target/role_prompt"]
          }
        ],
        provider_pool: []
      })

    assert {:ok, decision} =
             Trinity.Router.route(config, %{
               coordination_run_ref: "ai_run/coordination/invalid",
               preferred_role_ref: "role/missing",
               raw_prompt: "must not project",
               trace_ref: "trace/router/fallback"
             })

    projection = Trinity.RouterDecision.to_projection(decision)
    assert projection.selected_role_ref == "role/worker"
    assert projection.confidence_band == :fallback
    assert projection.fallback_reason == :invalid_route
    refute Map.has_key?(projection, :raw_prompt)
  end
end
