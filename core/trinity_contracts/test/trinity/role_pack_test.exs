defmodule Trinity.RolePackTest do
  use ExUnit.Case, async: true

  test "registry governs role prompt, capability, model, tool, memory, guardrail, budget, handoff, and GEPA refs" do
    assert {:ok, registry} =
             Trinity.Registry.new(%{
               role_packs: [
                 %{
                   role_ref: "role/verifier",
                   prompt_ref: "prompt/verifier",
                   capability_refs: ["cap/check"],
                   allowed_model_profile_refs: ["model/mock/verifier"],
                   tool_policy_ref: "tool/policy/verifier",
                   memory_profile_ref: "memory/role/verifier",
                   guardrail_profile_ref: "guardrail/role/verifier",
                   verifier_profile_ref: "verifier/role/verifier",
                   budget_ref: "budget/role/verifier",
                   context_budget_ref: "context/role/verifier",
                   handoff_policy_ref: "handoff/role/verifier",
                   projection_ref: "projection/role/verifier",
                   gepa_target_refs: ["gepa/target/verifier_prompt"]
                 }
               ]
             })

    assert {:ok, role_pack} = Trinity.Registry.fetch_role_pack(registry, "role/verifier")
    assert role_pack.role_ref == "role/verifier"
    assert role_pack.prompt_ref == "prompt/verifier"
    assert role_pack.allowed_model_profile_refs == ["model/mock/verifier"]
    assert role_pack.gepa_target_refs == ["gepa/target/verifier_prompt"]
  end

  test "raw prompts, memory bodies, provider payloads, tool bodies, and secrets are rejected" do
    base = %{
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

    for forbidden <- [:raw_prompt, :memory_body, :provider_payload, :tool_body, :secret] do
      assert {:error, {:forbidden_raw_field, ^forbidden}} =
               Trinity.RolePack.new(Map.put(base, forbidden, "raw"))
    end
  end
end
