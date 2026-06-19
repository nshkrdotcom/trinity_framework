defmodule Trinity.Examples.QwenRouterPromptEval.TraceOutTest do
  use ExUnit.Case, async: false

  alias Trinity.Examples.QwenRouterPromptEval

  test "trace-out emits route decision and eval result records per case" do
    path = Path.join(System.tmp_dir!(), "qwen-router-prompt-eval-trace-out.jsonl")
    File.rm(path)

    assert :ok =
             QwenRouterPromptEval.main([
               "--runtime-profile",
               "mock_tiny",
               "--determinism-runs",
               "2",
               "--case",
               "math_direct",
               "--trace-out",
               path,
               "--suppress-native-logs-child"
             ])

    records =
      path
      |> File.stream!()
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Enum.map(&Jason.decode!/1)

    assert [route, eval] = records
    assert route["event"] == "route_decision"
    assert route["case_id"] == "math_direct"
    assert route["route_path"] == "qwen_router_prompt_eval"
    assert is_binary(route["route_hash"])
    assert eval["event"] == "route_eval_result"
    assert eval["status"] == "report"
    assert eval["expected_agent_id"] == 4
    assert is_number(eval["agent_margin"])
  end
end
