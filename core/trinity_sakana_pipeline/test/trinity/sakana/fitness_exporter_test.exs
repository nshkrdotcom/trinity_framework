defmodule Trinity.Sakana.FitnessExporterTest do
  use ExUnit.Case, async: true

  alias Trinity.Sakana.FitnessExporter

  @fixtures Path.expand("../../fixtures/fitness_traces", __DIR__)

  test "exports scored examples and a manifest" do
    root = tmp_dir("export")
    out = Path.join(root, "fitness.jsonl")
    manifest_out = Path.join(root, "manifest.json")

    assert {:ok, summary} =
             FitnessExporter.export([fixture("orchestrator_accept.jsonl")],
               out: out,
               manifest_out: manifest_out
             )

    assert summary.record_count == 1
    assert summary.positive_count == 1
    assert File.exists?(out)
    assert File.exists?(manifest_out)
  end

  test "exports multiple route decisions from multiple traces" do
    assert {:ok, summary} =
             FitnessExporter.export(
               [fixture("orchestrator_accept.jsonl"), fixture("orchestrator_revise.jsonl")],
               dry_run: true
             )

    assert summary.record_count == 2
  end

  test "attributes a verifier revision penalty to the route that caused it" do
    root = tmp_dir("revision-attribution")
    out = Path.join(root, "fitness.jsonl")

    assert {:ok, %{record_count: 1}} =
             FitnessExporter.export([fixture("orchestrator_revise.jsonl")], out: out)

    example = out |> File.read!() |> String.trim() |> Jason.decode!()

    assert example["outcome"]["revision_count"] == 1
    assert_in_delta example["fitness"]["components"]["revision"], -0.1, 1.0e-12
  end

  test "skip_invalid preserves valid records and reports skipped lines" do
    assert {:ok, summary} =
             FitnessExporter.export([fixture("malformed_line.jsonl")],
               dry_run: true,
               skip_invalid: true
             )

    assert summary.record_count == 1
    assert summary.skipped_count == 1
  end

  defp fixture(name), do: Path.join(@fixtures, name)

  defp tmp_dir(name) do
    path = Path.join(System.tmp_dir!(), "trinity-fitness-exporter-#{name}")
    File.rm_rf!(path)
    path
  end
end
