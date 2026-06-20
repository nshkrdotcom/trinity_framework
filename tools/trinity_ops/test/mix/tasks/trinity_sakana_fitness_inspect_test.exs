defmodule Mix.Tasks.Trinity.Sakana.FitnessInspectTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Trinity.Sakana.FitnessInspect
  alias Trinity.Sakana.FitnessExporter

  @trace Path.expand(
           "../../../../../core/trinity_sakana_pipeline/test/fixtures/fitness_traces/orchestrator_accept.jsonl",
           __DIR__
         )

  test "json mode emits a fitness dataset report and writes out when requested" do
    %{fitness: fitness, manifest: manifest, out: out} = dataset("inspect-task")

    output =
      capture_io(fn ->
        FitnessInspect.run([
          "--fitness",
          fitness,
          "--manifest",
          manifest,
          "--out",
          out,
          "--json"
        ])
      end)

    assert %{"dataset_status" => "candidate_eval_ready"} = Jason.decode!(String.trim(output))
    assert File.exists?(out)
  end

  test "requires fitness path" do
    assert_raise Mix.Error, fn -> FitnessInspect.run(["--json"]) end
  end

  defp dataset(name) do
    dir = tmp_dir(name)
    fitness = Path.join(dir, "fitness.jsonl")
    manifest = Path.join(dir, "manifest.json")
    out = Path.join(dir, "inspect.json")

    assert {:ok, _summary} =
             FitnessExporter.export([@trace], out: fitness, manifest_out: manifest)

    %{fitness: fitness, manifest: manifest, out: out}
  end

  defp tmp_dir(name) do
    dir = Path.join(["tmp", "test", name])
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end
end
