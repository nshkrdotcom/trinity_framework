defmodule Trinity.Examples.QwenRouterPromptEval.ReflexReportTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Trinity.Examples.QwenRouterPromptEval

  test "reflex report prints per-case and aggregate classifications" do
    output =
      capture_io(fn ->
        assert :ok =
                 QwenRouterPromptEval.main([
                   "--runtime-profile",
                   "mock_tiny",
                   "--case",
                   "math_direct",
                   "--reflex-report",
                   "--suppress-native-logs-child"
                 ])
      end)

    assert String.contains?(output, "Reflex classification")
    assert String.contains?(output, "math_direct:")
    assert String.contains?(output, "high:")
    assert String.contains?(output, "medium:")
    assert String.contains?(output, "low:")
    assert String.contains?(output, "thinker_then_verifier:")
  end

  test "reflex trace emits paired route and reflex records" do
    path = tmp_path("reflex-trace.jsonl")

    assert :ok =
             QwenRouterPromptEval.main([
               "--runtime-profile",
               "mock_tiny",
               "--case",
               "math_direct",
               "--reflex-trace-out",
               path,
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
               "--suppress-native-logs-child"
             ])

    assert [route, reflex] = read_jsonl(path)
    assert route["event"] == "route_decision"
    assert route["runtime_profile"] == "mock_tiny"
    refute Map.has_key?(route, "artifact_root")
    refute Map.has_key?(route, "artifact_manifest_path")
    assert reflex["event"] == "reflex_decision"
    assert reflex["route_hash"] == route["route_hash"]
    assert reflex["confidence_class"] == "low"
    assert reflex["action"] == "thinker_then_verifier"
  end

  test "reflex analysis does not mutate existing eval trace status or route" do
    trace_path = tmp_path("eval-trace.jsonl")
    reflex_path = tmp_path("eval-reflex-trace.jsonl")

    assert :ok =
             QwenRouterPromptEval.main([
               "--runtime-profile",
               "mock_tiny",
               "--case",
               "math_direct",
               "--trace-out",
               trace_path,
               "--reflex-report",
               "--reflex-trace-out",
               reflex_path,
               "--suppress-native-logs-child"
             ])

    [route, eval] = read_jsonl(trace_path)
    [reflex_route, _reflex] = read_jsonl(reflex_path)

    assert eval["status"] == "report"
    assert reflex_route["selected_agent_id"] == route["selected_agent_id"]
    assert reflex_route["selected_role_id"] == route["selected_role_id"]
    assert reflex_route["route_hash"] == route["route_hash"]
  end

  defp read_jsonl(path) do
    path
    |> File.stream!()
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Enum.map(&Jason.decode!/1)
  end

  defp tmp_path(name) do
    root = Path.join(System.tmp_dir!(), "qwen-reflex-report-test")
    File.mkdir_p!(root)
    path = Path.join(root, name)
    File.rm(path)
    path
  end
end
