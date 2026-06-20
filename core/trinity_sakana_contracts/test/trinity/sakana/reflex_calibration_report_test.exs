defmodule Trinity.Sakana.ReflexCalibrationReportTest do
  use ExUnit.Case, async: true

  alias Trinity.Sakana.ReflexCalibrationReport

  test "builds a valid calibration report" do
    report =
      ReflexCalibrationReport.new!(
        fitness_path: "fitness.jsonl",
        record_count: 4,
        margin_mode: "profile_floor",
        candidate_count: 2,
        recommended_thresholds: %{"high_multiplier" => 4.0},
        recommended_score: 1.0,
        status: "ok",
        status_reason: nil,
        candidates: []
      )

    assert report.schema_version == ReflexCalibrationReport.schema_version()
  end
end
