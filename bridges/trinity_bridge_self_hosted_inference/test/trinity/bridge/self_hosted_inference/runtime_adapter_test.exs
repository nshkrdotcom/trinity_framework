defmodule Trinity.Bridge.SelfHostedInference.RuntimeAdapterTest do
  use ExUnit.Case, async: false

  alias Trinity.Bridge.SelfHostedInference
  alias Trinity.Bridge.SelfHostedInference.RuntimeAdapter

  alias Trinity.Coordinator.{
    AdapterRef,
    HiddenStateExtractionPlan,
    RouteLogits,
    RuntimeProfileRef
  }

  setup do
    Application.ensure_all_started(:self_hosted_inference_core)
    SelfHostedInferenceCore.stop_all_instances()

    on_exit(fn -> SelfHostedInferenceCore.stop_all_instances() end)

    :ok
  end

  test "loads a mock tiny adapter through self-hosted inference core" do
    plan = mock_plan()

    assert {:ok, %RuntimeAdapter{} = runtime} = RuntimeAdapter.load(plan)
    assert runtime.instance.backend == :bumblebee
    assert runtime.instance.adapter_ref.id == :mock_tiny
    assert runtime.loaded.runtime_profile == :mock_tiny
  end

  test "routes through the loaded adapter and returns Trinity route logits" do
    plan = mock_plan(messages: [%{role: "user", content: "Decompose this task"}])
    {:ok, runtime} = RuntimeAdapter.load(plan)

    assert {:ok, %RouteLogits{} = logits} = RuntimeAdapter.route(runtime, plan)
    assert logits.backend_label == :mock_tiny
    assert logits.runtime_profile == :mock_tiny
    assert logits.token_count == 3
    assert is_binary(logits.transcript_hash)
    assert is_integer(logits.selected_agent_id)
    assert is_integer(logits.selected_role_id)
  end

  test "top-level bridge delegates to the runtime adapter" do
    plan = mock_plan()

    assert {:ok, %RuntimeAdapter{} = runtime} = SelfHostedInference.load(plan)
    assert {:ok, %RouteLogits{}} = SelfHostedInference.route(runtime, plan)
  end

  defp mock_plan(attrs \\ []) do
    %HiddenStateExtractionPlan{
      adapter_ref:
        AdapterRef.new!(
          id: Keyword.get(attrs, :adapter_id, :mock_tiny),
          version: "0.1.0",
          contract: :route_logits_v1
        ),
      runtime_profile_ref: %RuntimeProfileRef{
        name: Keyword.get(attrs, :runtime_profile, :mock_tiny)
      },
      messages: Keyword.get(attrs, :messages, [%{role: "user", content: "hello trinity"}]),
      options: Keyword.get(attrs, :options, %{}),
      metadata: Keyword.get(attrs, :metadata, %{})
    }
  end
end
