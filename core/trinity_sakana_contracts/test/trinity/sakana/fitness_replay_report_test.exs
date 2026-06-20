defmodule Trinity.Sakana.FitnessReplayReportTest do
  use ExUnit.Case, async: true

  alias Trinity.Sakana.FitnessReplayReport

  test "builds a valid replay report" do
    report =
      FitnessReplayReport.new!(
        fitness_path: "fitness.jsonl",
        manifest_path: "manifest.json",
        record_count: 1,
        score_mismatch_count: 0,
        label_mismatch_count: 0,
        mismatches: [],
        component_summary: %{},
        group_summary: %{},
        reflex_economics: %{},
        dataset_digest: "sha256:abc",
        status: "ok",
        status_reason: nil
      )

    assert report.schema_version == FitnessReplayReport.schema_version()
  end

  test "rejects negative counts" do
    assert {:error, :invalid_counts} =
             FitnessReplayReport.new(
               fitness_path: "fitness.jsonl",
               manifest_path: nil,
               record_count: -1,
               score_mismatch_count: 0,
               label_mismatch_count: 0,
               mismatches: [],
               component_summary: %{},
               group_summary: %{},
               reflex_economics: %{},
               dataset_digest: nil,
               status: "invalid",
               status_reason: nil
             )
  end
end
