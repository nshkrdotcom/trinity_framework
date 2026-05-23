defmodule Trinity.ProviderPoolTest do
  use ExUnit.Case, async: true

  test "supports local, remote, self-hosted, mock, cli, http, and governed inference slots with per-role constraints" do
    slot_kinds = [:local, :remote, :self_hosted, :mock, :cli, :http, :governed_inference]

    slots =
      Enum.map(slot_kinds, fn kind ->
        slot = %{
          slot_ref: "slot/#{kind}",
          slot_kind: kind,
          role_refs: ["role/worker"],
          model_profile_ref: "model/#{kind}",
          endpoint_profile_ref: "endpoint/#{kind}",
          operation_policy_ref: "policy/#{kind}",
          target_ref: "target/#{kind}",
          credential_ref: "credential/#{kind}",
          per_role_constraints: %{
            "role/worker" => %{max_turns: 3, budget_ref: "budget/worker"}
          }
        }

        if kind == :self_hosted do
          Map.put(slot, :local_endpoint_ref, %{
            readiness_ref: "readiness/#{kind}",
            health_ref: "health/#{kind}",
            endpoint_lease_ref: "lease/#{kind}",
            target_attach_ref: "attach/#{kind}",
            endpoint_profile_ref: "endpoint/#{kind}",
            target_ref: "target/#{kind}"
          })
        else
          slot
        end
      end)

    assert {:ok, provider_pool} = Trinity.ProviderPool.new(slots)
    assert Enum.map(provider_pool.slots, & &1.slot_kind) == slot_kinds
    assert {:ok, slot} = Trinity.ProviderPool.slot_for_role(provider_pool, "role/worker")
    assert slot.role_refs == ["role/worker"]
  end

  test "rejects raw credentials and provider payloads" do
    base = %{
      slot_ref: "slot/mock",
      slot_kind: :mock,
      role_refs: ["role/worker"],
      model_profile_ref: "model/mock",
      endpoint_profile_ref: "endpoint/mock",
      operation_policy_ref: "policy/mock",
      target_ref: "target/mock",
      credential_ref: "credential/ref"
    }

    assert {:error, {:forbidden_raw_field, :api_key}} =
             Trinity.ProviderPool.new([Map.put(base, :api_key, "secret")])

    assert {:error, {:forbidden_raw_field, :provider_payload}} =
             Trinity.ProviderPool.new([Map.put(base, :provider_payload, %{body: "raw"})])
  end
end
