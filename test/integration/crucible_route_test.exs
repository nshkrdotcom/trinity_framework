defmodule TrinityFramework.Integration.CrucibleRouteTest do
  use ExUnit.Case, async: false

  alias Trinity.Coordinator.RouteDecision
  alias Trinity.SingleNode

  setup do
    Application.ensure_all_started(:trinity_single_node)
    SelfHostedInferenceCore.stop_all_instances()

    on_exit(fn ->
      SelfHostedInferenceCore.stop_all_instances()
    end)

    :ok
  end

  test "single-node route produces Crucible route targets" do
    messages = [%{"role" => "user", "content" => "Route this deterministic prompt."}]

    {:ok, runtime} =
      SingleNode.load_runtime(runtime_profile: :mock_tiny, messages: messages)

    assert {:ok, crucible} =
             SingleNode.route(messages,
               runtime: runtime,
               runtime_profile: :mock_tiny,
               coordination_run_ref: "run:crucible",
               trace_ref: "trace:crucible"
             )

    assert %RouteDecision{} = crucible.decision
    assert is_integer(crucible.decision.selected_role_id)
    assert is_integer(crucible.decision.selected_agent_id)
    assert crucible.decision.router_artifact_ref == "crucible_policy:trinity_route_logits"
    assert crucible.crucible_trace.trace_id == "trace:crucible"
    assert crucible.tap_plan.plan_id =~ "trinity:crucible:"
  end

  test "Crucible route path writes both Crucible and coordinator trace records" do
    trace_path =
      Path.join(
        System.tmp_dir!(),
        "trinity-crucible-route-#{System.unique_integer([:positive])}.jsonl"
      )

    messages = [%{"role" => "user", "content" => "Check this route."}]

    assert {:ok, result} =
             SingleNode.route(messages,
               runtime_profile: :mock_tiny,
               trace_path: trace_path,
               trace_ref: "trace:crucible-jsonl",
               coordination_run_ref: "run:crucible-jsonl"
             )

    records =
      trace_path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)

    events = Enum.map(records, &Map.fetch!(&1, "event"))
    forward_trace = Enum.find(records, &(&1["event"] == "crucible_forward_trace"))

    assert forward_trace["model_id"] == "trinity/mock-tiny-route-runtime"
    assert get_in(forward_trace, ["metadata", "backend_label"]) == "mock_tiny"
    assert get_in(forward_trace, ["metadata", "runtime_profile"]) == "mock_tiny"

    assert get_in(forward_trace, ["metadata", "artifact_ref"]) ==
             "artifact:mock-tiny-route-runtime"

    assert get_in(forward_trace, ["metadata", "selected_agent_id"]) ==
             result.decision.selected_agent_id

    assert get_in(forward_trace, ["metadata", "selected_role_id"]) ==
             result.decision.selected_role_id

    assert "crucible_forward_trace" in events
    assert "crucible_signal_record" in events
    assert "route_selected" in events
    assert result.trace_path == trace_path
  end
end
