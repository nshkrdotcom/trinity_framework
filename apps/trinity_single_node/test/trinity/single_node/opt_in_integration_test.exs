defmodule Trinity.SingleNode.OptInIntegrationTest do
  use ExUnit.Case, async: false

  alias Trinity.SingleNode
  alias Trinity.SingleNode.Config

  @cases_path "/home/home/p/g/n/trinity_coordinator/examples/fixtures/qwen_router_prompt_eval_cases.json"

  @tag :single_node_full
  test "host_exla single-node full path runs a three-case subset" do
    artifact_root = required_artifact_root!()
    cases = fixture_cases() |> Enum.take(3)

    assert {:ok, runtime} =
             SingleNode.load_runtime(
               runtime_profile: :host_exla,
               artifact_root: artifact_root,
               messages: []
             )

    for %{"messages" => messages} <- cases do
      assert {:ok, result} =
               SingleNode.route(messages,
                 runtime: runtime,
                 runtime_profile: :host_exla,
                 artifact_root: artifact_root
               )

      assert is_integer(result.decision.selected_agent_id)
      assert is_integer(result.decision.selected_role_id)
    end
  end

  @tag :single_node_cuda
  test "cuda_exla single-node route path runs all 37 cases" do
    artifact_root = required_artifact_root!()

    assert {:ok, runtime} =
             SingleNode.load_runtime(
               runtime_profile: :cuda_exla,
               artifact_root: artifact_root,
               messages: []
             )

    for %{"messages" => messages} <- fixture_cases() do
      assert {:ok, result} =
               SingleNode.route(messages,
                 runtime: runtime,
                 runtime_profile: :cuda_exla,
                 artifact_root: artifact_root
               )

      assert is_integer(result.decision.selected_agent_id)
      assert is_integer(result.decision.selected_role_id)
    end
  end

  defp required_artifact_root! do
    artifact_root = System.get_env("TRINITY_ARTIFACT_DIR") || Config.artifact_root()

    unless File.dir?(artifact_root) do
      raise "TRINITY_ARTIFACT_DIR must point at an adapted artifact directory"
    end

    artifact_root
  end

  defp fixture_cases do
    @cases_path
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("cases")
  end
end
