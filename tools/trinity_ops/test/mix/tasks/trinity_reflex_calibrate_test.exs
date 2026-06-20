defmodule Mix.Tasks.Trinity.Reflex.CalibrateTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Trinity.Reflex.Calibrate
  alias Trinity.Sakana.FitnessExporter

  @trace Path.expand(
           "../../../../../core/trinity_sakana_pipeline/test/fixtures/fitness_traces/orchestrator_accept.jsonl",
           __DIR__
         )

  test "json mode emits calibration report" do
    fitness = dataset("calibrate-task")

    output =
      capture_io(fn ->
        Calibrate.run([
          "--fitness",
          fitness,
          "--high-multiplier",
          "4.0",
          "--low-multiplier",
          "1.0",
          "--json"
        ])
      end)

    assert %{"schema_version" => "trinity.reflex.calibration_report.v1", "status" => "ok"} =
             Jason.decode!(String.trim(output))
  end

  test "invalid multiplier fails clearly" do
    fitness = dataset("calibrate-invalid")

    assert_raise Mix.Error, fn ->
      Calibrate.run(["--fitness", fitness, "--high-multiplier", "bad"])
    end
  end

  defp dataset(name) do
    dir = Path.join(["tmp", "test", name])
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    fitness = Path.join(dir, "fitness.jsonl")
    assert {:ok, _summary} = FitnessExporter.export([@trace], out: fitness)
    fitness
  end
end
