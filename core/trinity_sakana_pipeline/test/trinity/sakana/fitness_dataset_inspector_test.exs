defmodule Trinity.Sakana.FitnessDatasetInspectorTest do
  use ExUnit.Case, async: true

  alias Trinity.Sakana.{FitnessDatasetInspector, FitnessExporter}

  @trace Path.expand("../../fixtures/fitness_traces/orchestrator_accept.jsonl", __DIR__)

  test "valid dataset verifies manifest digest and is candidate-eval-ready" do
    %{fitness: fitness, manifest: manifest} = export_dataset("inspect-valid")

    assert {:ok, report} = FitnessDatasetInspector.inspect(fitness, manifest: manifest)

    assert report.schema_version == "trinity.sakana.fitness_dataset_report.v1"
    assert report.record_count == 1
    assert report.positive_count == 1
    assert report.manifest_digest_verified == true
    assert report.dataset_status == "candidate_eval_ready"
    assert report.secret_scan["ok"] == true
  end

  test "manifest digest mismatch is invalid" do
    %{fitness: fitness, manifest: manifest} = export_dataset("inspect-mismatch")
    File.write!(manifest, ~s({"dataset_digest":"sha256:not-the-digest"}\n))

    assert {:ok, report} = FitnessDatasetInspector.inspect(fitness, manifest: manifest)
    assert report.dataset_status == "invalid"
    assert report.status_reason == "manifest_digest_mismatch"
  end

  test "secret-bearing exported rows are rejected" do
    dir = tmp_dir("inspect-secret")
    fitness = Path.join(dir, "fitness.jsonl")

    File.write!(
      fitness,
      ~s({"example_id":"fitness:secret","fitness":{"label":"neutral"},"source":{"kind":"test"},"route":{},"outcome":{"verifier_status":"unknown"},"api_key":"SECRET"}\n)
    )

    assert {:ok, report} = FitnessDatasetInspector.inspect(fitness)
    assert report.dataset_status == "invalid"
    assert report.status_reason == "secret_scan_failed"
  end

  defp export_dataset(name) do
    dir = tmp_dir(name)
    fitness = Path.join(dir, "fitness.jsonl")
    manifest = Path.join(dir, "manifest.json")

    assert {:ok, _summary} =
             FitnessExporter.export([@trace], out: fitness, manifest_out: manifest)

    %{fitness: fitness, manifest: manifest}
  end

  defp tmp_dir(name) do
    dir = Path.join(["tmp", "test", name])
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end
end
