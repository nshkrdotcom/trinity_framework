defmodule Trinity.SingleNode.ApplicationLifecycleTest do
  use ExUnit.Case, async: false

  alias Trinity.Coordinator.AdapterRef
  alias Trinity.SingleNode.RuntimeSupervisor

  setup do
    Application.ensure_all_started(:trinity_single_node)
    SelfHostedInferenceCore.stop_all_instances()

    on_exit(fn ->
      SelfHostedInferenceCore.stop_all_instances()
      Application.stop(:trinity_single_node)
    end)

    :ok
  end

  test "application boots and registers the Bumblebee backend" do
    assert {:ok, manifest} = SelfHostedInferenceCore.fetch_backend_manifest(:bumblebee)
    assert manifest.capabilities.route_logits? == true
  end

  test "runtime supervisor acquires and reuses leases by adapter ref" do
    assert {:ok, first} = RuntimeSupervisor.acquire_lease(runtime_profile: :mock_tiny)
    assert first.instance.adapter_ref.id == :mock_tiny
    assert first.endpoint.protocol == :route_logits

    assert {:ok, second} = RuntimeSupervisor.acquire_lease(runtime_profile: :mock_tiny)
    assert second.instance.instance_id == first.instance.instance_id

    other_adapter =
      AdapterRef.new!(id: :mock_tiny_other, version: "0.1.0", contract: :route_logits_v1)

    assert {:ok, third} =
             RuntimeSupervisor.acquire_lease(
               runtime_profile: :mock_tiny,
               adapter_ref: other_adapter
             )

    assert third.instance.instance_id != first.instance.instance_id
  end
end
