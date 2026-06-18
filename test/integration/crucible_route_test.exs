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

  test "Crucible route rejects requested identity that conflicts with loaded runtime" do
    artifact_root = Path.join(tmp_dir("custom-artifact"), "custom-artifact")
    File.mkdir_p!(artifact_root)

    write_json!(Path.join(artifact_root, "manifest.json"), %{
      "base_model_repo" => "example/non-qwen-router",
      "router_head_shape" => [4, 16],
      "selected_tensor_count" => 2,
      "scale_offset_count" => 12,
      "source_vector_shape" => [76]
    })

    manifest_sha = sha256_file(Path.join(artifact_root, "manifest.json"))

    write_json!(Path.join(artifact_root, "artifact_pin.json"), %{
      "repo_id" => "example/custom-artifact",
      "revision" => "custom-v2",
      "manifest_sha256" => manifest_sha
    })

    messages = [%{"role" => "user", "content" => "Route with custom provenance."}]

    {:ok, runtime} =
      SingleNode.load_runtime(runtime_profile: :mock_tiny, messages: messages)

    assert {:error, {:runtime_identity_mismatch, details}} =
             SingleNode.route(messages,
               runtime: runtime,
               runtime_profile: :custom,
               artifact_root: artifact_root,
               trace_ref: "trace:custom-artifact",
               coordination_run_ref: "run:custom-artifact"
             )

    assert details.reason == :runtime_profile
    assert details.requested_profile == :custom
    assert details.requested_artifact_ref =~ "artifact:example_custom-artifact:custom-v2:"
    assert details.executed_profile == :mock_tiny
    assert details.executed_artifact_ref == "artifact:mock-tiny-route-runtime"
  end

  defp tmp_dir(name) do
    path = Path.join(System.tmp_dir!(), "trinity-crucible-route-#{name}")
    File.rm_rf!(path)
    path
  end

  defp write_json!(path, payload) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(payload))
  end

  defp sha256_file(path) do
    path
    |> File.read!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
