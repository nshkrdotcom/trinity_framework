defmodule Trinity.LocalEndpointTest do
  use ExUnit.Case, async: true

  test "self-hosted endpoint slots require readiness, health, lease, target attach, endpoint, and target refs" do
    assert {:ok, provider_pool} =
             Trinity.ProviderPool.new([
               %{
                 slot_ref: "slot/self-hosted",
                 slot_kind: :self_hosted,
                 role_refs: ["role/worker"],
                 model_profile_ref: "model/local/qwen",
                 endpoint_profile_ref: "endpoint/local/qwen",
                 operation_policy_ref: "policy/local/route",
                 target_ref: "target/local/qwen",
                 credential_ref: "credential/local/ref",
                 local_endpoint_ref: %{
                   readiness_ref: "readiness/local/qwen",
                   health_ref: "health/local/qwen",
                   endpoint_lease_ref: "lease/local/qwen",
                   target_attach_ref: "attach/local/qwen",
                   endpoint_profile_ref: "endpoint/local/qwen",
                   target_ref: "target/local/qwen"
                 }
               }
             ])

    [slot] = provider_pool.slots
    assert slot.local_endpoint_ref.readiness_ref == "readiness/local/qwen"
    assert slot.local_endpoint_ref.endpoint_lease_ref == "lease/local/qwen"
    assert slot.local_endpoint_ref.target_attach_ref == "attach/local/qwen"
    assert slot.endpoint_identity_ref == "endpoint/local/qwen"
    assert slot.provider_credential_identity_ref == "credential/local/ref"
    refute slot.endpoint_identity_ref == slot.provider_credential_identity_ref
  end

  test "self-hosted endpoint slots reject missing local endpoint posture refs" do
    assert {:error, {:missing_required_field, :local_endpoint_ref}} =
             Trinity.ProviderPool.new([
               %{
                 slot_ref: "slot/self-hosted",
                 slot_kind: :self_hosted,
                 role_refs: ["role/worker"],
                 model_profile_ref: "model/local/qwen",
                 endpoint_profile_ref: "endpoint/local/qwen",
                 operation_policy_ref: "policy/local/route",
                 target_ref: "target/local/qwen",
                 credential_ref: "credential/local/ref"
               }
             ])
  end
end
