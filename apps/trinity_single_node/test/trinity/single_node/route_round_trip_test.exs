defmodule Trinity.SingleNode.RouteRoundTripTest do
  use ExUnit.Case, async: false

  alias Trinity.Coordinator.{RouteDecision, RouteLogits}
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

  test "mock_tiny route round-trip derives public router decision and trace JSONL" do
    trace_path = tmp_path("route")
    messages = [%{role: "user", content: "Route this deterministic prompt."}]

    assert {:ok, result} =
             SingleNode.route(messages,
               runtime_profile: :mock_tiny,
               trace_path: trace_path,
               timestamp_ms: 1_700_000_000_000
             )

    assert %RouteLogits{} = result.logits
    assert %RouteDecision{} = result.decision
    assert result.router_decision.router_decision_ref == result.decision.router_decision_ref
    assert result.decision.transcript_hash == result.logits.transcript_hash

    assert result.decision.transcript_hash ==
             "6f7d00cd47d137afbaf4bf479a305cd2e11b5ceb4138230648eb21a57c9e5106"

    decoded_events =
      trace_path
      |> File.stream!()
      |> Enum.map(&Jason.decode!/1)

    route_event = Enum.find(decoded_events, &(&1["event"] == "route_selected"))

    assert route_event["transcript_hash"] == result.decision.transcript_hash
    assert route_event["token_count"] == 4
    assert Enum.any?(decoded_events, &(&1["event"] == "crucible_forward_trace"))
  end

  defp tmp_path(label) do
    Path.join(
      System.tmp_dir!(),
      "trinity-single-node-#{label}-#{System.unique_integer([:positive])}.jsonl"
    )
  end
end
