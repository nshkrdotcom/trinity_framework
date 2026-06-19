defmodule Mix.Tasks.Trinity.Sakana.FitnessExportTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Trinity.Sakana.FitnessExport

  @fixture Path.expand(
             "../../../../../core/trinity_sakana_pipeline/test/fixtures/fitness_traces/orchestrator_accept.jsonl",
             __DIR__
           )

  test "writes fitness JSONL and manifest" do
    root = tmp_dir("write")
    out = Path.join(root, "fitness.jsonl")
    manifest = Path.join(root, "manifest.json")

    FitnessExport.run([
      "--trace",
      @fixture,
      "--out",
      out,
      "--manifest-out",
      manifest
    ])

    assert File.stat!(out).size > 0
    assert File.stat!(manifest).size > 0
  end

  test "json mode prints only a machine-readable summary" do
    root = tmp_dir("json")
    out = Path.join(root, "fitness.jsonl")

    output =
      capture_io(fn ->
        FitnessExport.run([
          "--trace",
          @fixture,
          "--out",
          out,
          "--json"
        ])
      end)

    assert %{"ok" => true, "record_count" => 1} = Jason.decode!(String.trim(output))
  end

  test "dry-run requires no output and writes no files" do
    root = tmp_dir("dry")
    out = Path.join(root, "fitness.jsonl")

    FitnessExport.run([
      "--trace",
      @fixture,
      "--out",
      out,
      "--dry-run"
    ])

    refute File.exists?(out)
  end

  test "requires at least one trace" do
    assert_raise Mix.Error, fn ->
      FitnessExport.run(["--dry-run"])
    end
  end

  defp tmp_dir(name) do
    path = Path.join(System.tmp_dir!(), "trinity-fitness-task-#{name}")
    File.rm_rf!(path)
    path
  end
end
