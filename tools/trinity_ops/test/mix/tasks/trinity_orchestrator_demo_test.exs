defmodule Mix.Tasks.Trinity.Orchestrator.DemoTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Trinity.Orchestrator.Demo

  setup do
    SelfHostedInferenceCore.stop_all_instances()

    on_exit(fn -> SelfHostedInferenceCore.stop_all_instances() end)
    :ok
  end

  test "mock demo runs the coordinator Orchestrator and emits fitness-bearing events" do
    trace_path = tmp_path("orchestrator.jsonl")

    Demo.run([
      "--runtime-profile",
      "mock_tiny",
      "--mock-provider",
      "--max-turns",
      "3",
      "--trace-out",
      trace_path
    ])

    records = read_jsonl(trace_path)
    events = Enum.map(records, & &1["event"])

    assert "route_decision" in events
    assert "reflex_decision" in events
    assert "provider_dispatch_started" in events
    assert "provider_dispatch_finished" in events
    assert "verifier_result" in events
    assert "budget_snapshot" in events
    assert "run_finished" in events

    verifier = Enum.find(records, &(&1["event"] == "verifier_result"))
    assert verifier["status"] == "accepted"
    assert verifier["safe_status"] == "accepted"

    finished = Enum.find(records, &(&1["event"] == "provider_dispatch_finished"))
    assert is_integer(finished["latency_ms"])
    assert finished["provider"] == "mock"
    refute Map.has_key?(finished, "text")
  end

  test "json mode emits one machine-readable summary" do
    trace_path = tmp_path("orchestrator-json.jsonl")

    output =
      capture_io(fn ->
        Demo.run([
          "--runtime-profile",
          "mock_tiny",
          "--mock-provider",
          "--max-turns",
          "1",
          "--trace-out",
          trace_path,
          "--json"
        ])
      end)

    assert %{
             "ok" => true,
             "trace_path" => ^trace_path,
             "reflex_enabled" => true,
             "reflex_decisions" => reflex_decisions,
             "direct_dispatch_count" => direct,
             "normal_dispatch_count" => normal,
             "thinker_then_verifier_count" => escalation
           } = Jason.decode!(String.trim(output))

    assert reflex_decisions == direct + normal + escalation
    assert reflex_decisions > 0
  end

  test "no-reflex preserves dispatch and reports disabled decisions" do
    trace_path = tmp_path("orchestrator-no-reflex.jsonl")

    output =
      capture_io(fn ->
        Demo.run([
          "--runtime-profile",
          "mock_tiny",
          "--mock-provider",
          "--max-turns",
          "1",
          "--no-reflex",
          "--trace-out",
          trace_path,
          "--json"
        ])
      end)

    summary = Jason.decode!(String.trim(output))
    assert summary["reflex_enabled"] == false
    assert summary["reflex_decisions"] == 1
    assert summary["normal_dispatch_count"] == 1

    reflex = read_jsonl(trace_path) |> Enum.find(&(&1["event"] == "reflex_decision"))
    assert reflex["reflex_enabled"] == false
    assert reflex["reason"] == "disabled"
  end

  test "explicit absolute thresholds can force low-confidence escalation" do
    trace_path = tmp_path("orchestrator-reflex-low.jsonl")

    output =
      capture_io(fn ->
        Demo.run([
          "--runtime-profile",
          "mock_tiny",
          "--mock-provider",
          "--max-turns",
          "3",
          "--reflex",
          "--reflex-margin-mode",
          "absolute",
          "--reflex-low-agent-margin",
          "999.0",
          "--reflex-low-role-margin",
          "999.0",
          "--reflex-high-agent-margin",
          "1000.0",
          "--reflex-high-role-margin",
          "1000.0",
          "--trace-out",
          trace_path,
          "--json"
        ])
      end)

    summary = Jason.decode!(String.trim(output))
    assert summary["thinker_then_verifier_count"] >= 1

    dispatch_roles =
      trace_path
      |> read_jsonl()
      |> Enum.filter(&(&1["event"] == "provider_dispatch_started"))
      |> Enum.map(& &1["selected_role_id"])

    assert Enum.take(dispatch_roles, 2) == [1, 2]
  end

  test "invalid reflex enums fail clearly" do
    exception =
      assert_raise Mix.Error, fn ->
        Demo.run([
          "--runtime-profile",
          "mock_tiny",
          "--mock-provider",
          "--reflex-margin-mode",
          "unsafe-mode",
          "--trace-out",
          tmp_path("invalid-reflex.jsonl")
        ])
      end

    assert Exception.message(exception) =~ "invalid_reflex_margin_mode"
  end

  test "live execution is rejected unless explicitly allowed" do
    assert_raise Mix.Error, fn ->
      Demo.run([
        "--runtime-profile",
        "mock_tiny",
        "--trace-out",
        tmp_path("live-rejected.jsonl")
      ])
    end
  end

  test "default hash trace does not persist raw prompt credentials" do
    trace_path = tmp_path("orchestrator-secret.jsonl")
    secret = "Bearer SECRET-ORCHESTRATOR-TOKEN"

    Demo.run([
      "--runtime-profile",
      "mock_tiny",
      "--mock-provider",
      "--max-turns",
      "1",
      "--message",
      secret,
      "--trace-out",
      trace_path
    ])

    trace = File.read!(trace_path)
    refute String.contains?(trace, secret)
    refute String.contains?(trace, "SECRET-ORCHESTRATOR-TOKEN")
  end

  defp read_jsonl(path) do
    path
    |> File.stream!()
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Enum.map(&Jason.decode!/1)
  end

  defp tmp_path(name) do
    root = Path.join(System.tmp_dir!(), "trinity-orchestrator-demo-test")
    File.rm_rf!(root)
    File.mkdir_p!(root)
    Path.join(root, name)
  end
end
