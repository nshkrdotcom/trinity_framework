defmodule Trinity.SingleNode.ProviderDispatchTest do
  use ExUnit.Case, async: false

  alias Trinity.SingleNode

  setup do
    Application.ensure_all_started(:trinity_single_node)
    SelfHostedInferenceCore.stop_all_instances()

    on_exit(fn ->
      SelfHostedInferenceCore.stop_all_instances()
      Application.stop(:trinity_single_node)
    end)

    :ok
  end

  test "mock provider dispatch returns a deterministic receipt" do
    messages = [%{role: "user", content: "summarize"}]
    {:ok, route} = SingleNode.route(messages, runtime_profile: :mock_tiny)

    assert {:ok, receipt} =
             SingleNode.dispatch(route, messages,
               provider_pool: :mock,
               mock_response: "mock completion"
             )

    assert receipt.status == :ok
    assert receipt.metadata.text == "mock completion"
    assert receipt.metadata.provider == :mock
  end

  test "live provider dispatch refuses without explicit approval" do
    messages = [%{role: "user", content: "summarize"}]
    {:ok, route} = SingleNode.route(messages, runtime_profile: :mock_tiny)

    assert {:error, :live_provider_not_allowed} =
             SingleNode.dispatch(route, messages, provider_pool: :default)
  end

  test "provider trace redacts API keys" do
    trace_path = tmp_path("provider")
    messages = [%{role: "user", content: "summarize"}]
    {:ok, route} = SingleNode.route(messages, runtime_profile: :mock_tiny)

    assert {:ok, _receipt} =
             SingleNode.dispatch(route, messages,
               provider_pool: :mock,
               mock_response: "mock completion",
               trace_path: trace_path,
               api_key: "secret-provider-key",
               redaction_values: ["secret-provider-key"]
             )

    lines = trace_path |> File.read!() |> String.split("\n", trim: true)
    provider = lines |> List.last() |> Jason.decode!()

    assert provider["event"] == "provider_called"
    assert provider["api_key"] == "<redacted>"
  end

  defp tmp_path(label) do
    Path.join(
      System.tmp_dir!(),
      "trinity-single-node-#{label}-#{System.unique_integer([:positive])}.jsonl"
    )
  end
end
