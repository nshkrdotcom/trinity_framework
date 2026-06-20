defmodule Trinity.Sakana.FitnessDatasetReportTest do
  use ExUnit.Case, async: true

  alias Trinity.Sakana.FitnessDatasetReport

  test "builds a valid dataset report" do
    report =
      FitnessDatasetReport.new!(
        fitness_path: "fitness.jsonl",
        manifest_path: "manifest.json",
        record_count: 2,
        positive_count: 1,
        neutral_count: 1,
        negative_count: 0,
        source_counts: %{"orchestrator" => 2},
        runtime_profiles: %{"mock_tiny" => 2},
        artifact_refs: %{},
        route_path_counts: %{},
        reflex_counts: %{},
        missing_outcome_counts: %{},
        secret_scan: %{"ok" => true, "findings" => []},
        digest: "sha256:abc",
        manifest_digest_verified: true,
        dataset_status: "replay_ready",
        status_reason: nil
      )

    assert report.schema_version == FitnessDatasetReport.schema_version()
    assert FitnessDatasetReport.to_map(report).record_count == 2
  end

  test "rejects unknown dataset status" do
    assert {:error, {:invalid_dataset_status, "ready-ish"}} =
             FitnessDatasetReport.new(
               fitness_path: "fitness.jsonl",
               manifest_path: nil,
               record_count: 0,
               positive_count: 0,
               neutral_count: 0,
               negative_count: 0,
               source_counts: %{},
               runtime_profiles: %{},
               artifact_refs: %{},
               route_path_counts: %{},
               reflex_counts: %{},
               missing_outcome_counts: %{},
               secret_scan: %{},
               digest: nil,
               manifest_digest_verified: false,
               dataset_status: "ready-ish",
               status_reason: nil
             )
  end
end
