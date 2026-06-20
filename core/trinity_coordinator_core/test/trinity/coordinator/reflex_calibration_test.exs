defmodule Trinity.Coordinator.ReflexCalibrationTest do
  use ExUnit.Case, async: true

  alias Trinity.Coordinator.ReflexCalibration
  alias Trinity.Sakana.MarginDefaults

  test "stable fixture yields recommended thresholds" do
    floors = MarginDefaults.defaults("mock_tiny")

    examples = [
      example(floors.agent * 8.0, floors.role * 8.0, "accepted"),
      example(floors.agent * 0.5, floors.role * 0.5, "rejected")
    ]

    assert {:ok, report} = ReflexCalibration.calibrate(examples, margin_mode: :profile_floor)

    assert report.schema_version == "trinity.reflex.calibration_report.v1"
    assert report.status == "ok"
    assert report.candidate_count > 0
    assert is_map(report.recommended_thresholds)
  end

  test "insufficient evidence is explicit" do
    assert {:ok, report} = ReflexCalibration.calibrate([])

    assert report.status == "insufficient_evidence"
    assert report.record_count == 0
  end

  test "absolute mode uses provided multipliers as thresholds" do
    examples = [
      example(10.0, 10.0, "accepted"),
      example(0.1, 0.1, "rejected")
    ]

    assert {:ok, report} =
             ReflexCalibration.calibrate(examples,
               margin_mode: :absolute,
               high_multipliers: [1.0],
               low_multipliers: [0.5]
             )

    assert report.status == "ok"
    assert report.candidate_count == 1
  end

  test "invalid enum fails closed" do
    assert_raise ArgumentError, fn ->
      ReflexCalibration.calibrate([example(1.0, 1.0, "accepted")], margin_mode: "unsafe")
    end
  end

  defp example(agent_margin, role_margin, status) do
    %{
      "route" => %{
        "agent_margin" => agent_margin,
        "role_margin" => role_margin,
        "runtime_profile" => "mock_tiny"
      },
      "outcome" => %{"verifier_status" => status}
    }
  end
end
