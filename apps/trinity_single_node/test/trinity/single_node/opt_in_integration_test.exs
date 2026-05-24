defmodule Trinity.SingleNode.OptInIntegrationTest do
  use ExUnit.Case, async: false

  alias Trinity.SingleNode
  alias Trinity.SingleNode.Config

  @fixtures_root Path.expand("../../../../../examples/qwen_router_prompt_eval/fixtures", __DIR__)
  @cases_path Path.join(@fixtures_root, "qwen_router_prompt_eval_cases.json")
  @snapshot_path Path.join(@fixtures_root, "qwen_router_prompt_eval_logits.json")

  @tag :single_node_full
  test "host_exla single-node full path matches a three-case coordinator subset" do
    artifact_root = required_artifact_root!()
    cases = fixture_cases_with_snapshot() |> Enum.take(3)

    assert {:ok, runtime} =
             SingleNode.load_runtime(
               runtime_profile: :host_exla,
               artifact_root: artifact_root,
               messages: []
             )

    for case_spec <- cases do
      assert_route_matches_snapshot!(runtime, case_spec,
        runtime_profile: :host_exla,
        artifact_root: artifact_root
      )
    end
  end

  @tag :single_node_cuda
  @tag timeout: 300_000
  test "cuda_exla single-node route path matches all 37 coordinator cases" do
    artifact_root = required_artifact_root!()

    assert {:ok, runtime} =
             SingleNode.load_runtime(
               runtime_profile: :cuda_exla,
               artifact_root: artifact_root,
               messages: []
             )

    cases = fixture_cases_with_snapshot()
    assert length(cases) == 37

    for case_spec <- cases do
      first =
        assert_route_matches_snapshot!(runtime, case_spec,
          runtime_profile: :cuda_exla,
          artifact_root: artifact_root
        )

      second =
        assert_route_matches_snapshot!(runtime, case_spec,
          runtime_profile: :cuda_exla,
          artifact_root: artifact_root
        )

      assert second.decision.route_hash == first.decision.route_hash
    end
  end

  defp required_artifact_root! do
    artifact_root = Config.artifact_root()

    unless File.dir?(artifact_root) do
      raise "configured artifact_root must point at an adapted artifact directory"
    end

    artifact_root
  end

  defp fixture_cases do
    @cases_path
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("cases")
  end

  defp fixture_cases_with_snapshot do
    snapshot_by_id =
      @snapshot_path
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("cases")
      |> Map.new(&{Map.fetch!(&1, "id"), &1})

    Enum.map(fixture_cases(), fn case_spec ->
      Map.put(case_spec, "snapshot", Map.fetch!(snapshot_by_id, Map.fetch!(case_spec, "id")))
    end)
  end

  defp assert_route_matches_snapshot!(runtime, case_spec, opts) do
    %{"messages" => messages, "snapshot" => snapshot} = case_spec

    assert {:ok, result} =
             SingleNode.route(messages, Keyword.merge(opts, runtime: runtime))

    assert result.decision.selected_agent_id == snapshot["agent_id"]
    assert result.decision.selected_role_id == snapshot["role_id"]
    assert result.decision.token_count == snapshot["token_count"]
    assert result.decision.transcript_hash == snapshot["transcript_hash"]

    result
  end
end
