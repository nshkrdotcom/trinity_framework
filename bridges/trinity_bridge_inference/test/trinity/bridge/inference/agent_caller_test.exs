defmodule Trinity.Bridge.Inference.AgentCallerTest do
  use ExUnit.Case, async: true

  alias Trinity.Bridge.Inference.AgentCaller
  alias Trinity.Bridge.Inference.ProviderPool
  alias Trinity.Bridge.Inference.TestSupport.MockProvider
  alias Trinity.Coordinator.{AgentCallIntent, AgentCallReceipt}

  test "mock provider path reproduces coordinator mock behavior" do
    intent = intent(agent_ref: "agent:2", messages: [%{role: "user", content: "ship it"}])

    assert {:ok, %AgentCallReceipt{} = receipt} =
             AgentCaller.call(intent, provider_pool: :mock, adapter: MockProvider)

    assert receipt.status == :ok
    assert receipt.metadata.text == "MOCK agent=2 model=mock-agent-2: ship it"
  end

  test "live provider path fails closed without explicit approval" do
    intent = intent(agent_ref: "agent:0")

    assert {:error, :live_provider_not_allowed} =
             AgentCaller.call(intent, provider_pool: :default)
  end

  test "role prompt is injected before dispatch" do
    parent = self()

    fun = fn _spec, messages, _opts ->
      send(parent, {:messages, messages})
      "ok"
    end

    intent = intent(role_ref: "Verifier")

    assert {:ok, %AgentCallReceipt{}} =
             AgentCaller.call(intent,
               provider_pool: :mock,
               adapter: MockProvider,
               mock_agent_fn: fun
             )

    assert_receive {:messages, [%{role: "system", content: content} | _rest]}
    assert content =~ "ACCEPT or REVISE"
  end

  test "response envelope conversion through :inference mock adapter" do
    intent = intent(agent_ref: "agent:1", messages: [%{role: "user", content: "summarize"}])

    assert {:ok, %AgentCallReceipt{} = receipt} =
             AgentCaller.call(intent,
               provider_pool: ProviderPool.fetch!(:mock),
               mock_response: "done"
             )

    assert receipt.metadata.text == "done"
    assert receipt.metadata.provider == :mock
    assert receipt.metadata.model == "mock-agent-1"
  end

  defp intent(attrs) do
    %AgentCallIntent{
      intent_ref: Keyword.get(attrs, :intent_ref, "intent:test"),
      role_ref: Keyword.get(attrs, :role_ref, "Worker"),
      agent_ref: Keyword.get(attrs, :agent_ref, "agent:0"),
      trace_ref: Keyword.get(attrs, :trace_ref, "trace:test"),
      messages: Keyword.get(attrs, :messages, [%{role: "user", content: "hello"}]),
      metadata: Keyword.get(attrs, :metadata, %{})
    }
  end
end
