defmodule Mix.Tasks.Trinity.Sakana.FitnessReplayTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Trinity.Sakana.FitnessReplay
  alias Trinity.Sakana.FitnessExporter

  @trace Path.expand(
           "../../../../../core/trinity_sakana_pipeline/test/fixtures/fitness_traces/orchestrator_reflex_low_margin.jsonl",
           __DIR__
         )

  test "json mode emits replay report" do
    %{fitness: fitness, manifest: manifest} = dataset("replay-task")

    output =
      capture_io(fn ->
        FitnessReplay.run([
          "--fitness",
          fitness,
          "--manifest",
          manifest,
          "--json"
        ])
      end)

    assert %{"status" => "ok", "record_count" => 1} = Jason.decode!(String.trim(output))
  end

  defp dataset(name) do
    dir = Path.join(["tmp", "test", name])
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    fitness = Path.join(dir, "fitness.jsonl")
    manifest = Path.join(dir, "manifest.json")

    assert {:ok, _summary} =
             FitnessExporter.export([@trace], out: fitness, manifest_out: manifest)

    %{fitness: fitness, manifest: manifest}
  end
end
