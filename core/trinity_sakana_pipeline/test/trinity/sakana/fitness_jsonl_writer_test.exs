defmodule Trinity.Sakana.FitnessJsonlWriterTest do
  use ExUnit.Case, async: true

  alias Trinity.Sakana.{FitnessExample, FitnessJsonlWriter}

  test "writes canonical JSONL and manifest with deterministic digests" do
    root = tmp_dir("writer")
    out = Path.join(root, "fitness.jsonl")
    manifest_out = Path.join(root, "manifest.json")
    example = example()

    assert {:ok, first} =
             FitnessJsonlWriter.write([example],
               out: out,
               manifest_out: manifest_out,
               source_trace_paths: ["trace.jsonl"]
             )

    assert File.exists?(out)
    assert File.exists?(manifest_out)
    assert first.manifest.record_count == 1

    assert %{"outcome" => %{"budget_exceeded" => false, "dispatch_ok" => true}} =
             out |> File.read!() |> Jason.decode!()

    assert {:ok, second} =
             FitnessJsonlWriter.write([example],
               out: out,
               manifest_out: manifest_out,
               source_trace_paths: ["trace.jsonl"]
             )

    assert first.manifest.dataset_digest == second.manifest.dataset_digest
    assert first.manifest.route_hashes_digest == second.manifest.route_hashes_digest
  end

  test "dry-run writes no files" do
    root = tmp_dir("dry-run")
    out = Path.join(root, "fitness.jsonl")

    assert {:ok, result} =
             FitnessJsonlWriter.write([example()], out: out, dry_run: true)

    refute File.exists?(out)
    assert result.manifest.record_count == 1
  end

  defp example do
    FitnessExample.new!(
      example_id: "fitness:1",
      source: %{"kind" => "orchestrator"},
      input: %{"transcript_hash" => "tx"},
      route: %{"route_hash" => "route-1", "runtime_profile" => "mock_tiny"},
      outcome: %{
        "verifier_status" => "accepted",
        "budget_exceeded" => false,
        "dispatch_ok" => true
      },
      fitness: %{"score" => 0.8, "label" => "positive"},
      provenance: %{"artifact_ref" => "artifact:mock"}
    )
  end

  defp tmp_dir(name) do
    path = Path.join(System.tmp_dir!(), "trinity-fitness-writer-#{name}")
    File.rm_rf!(path)
    path
  end
end
