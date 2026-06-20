defmodule Trinity.Sakana.FitnessReplayTest do
  use ExUnit.Case, async: true

  alias Trinity.Sakana.{FitnessExporter, FitnessReplay}

  @trace Path.expand(
           "../../fixtures/fitness_traces/orchestrator_reflex_low_margin.jsonl",
           __DIR__
         )

  test "replays stored score and aggregates reflex economics" do
    %{fitness: fitness, manifest: manifest} = export_dataset("replay-valid")

    assert {:ok, report} = FitnessReplay.replay(fitness, manifest: manifest)

    assert report.record_count == 1
    assert report.score_mismatch_count == 0
    assert report.label_mismatch_count == 0
    assert report.reflex_economics["thinker_then_verifier"]["count"] == 1
  end

  test "tampered label and score are reported" do
    %{fitness: fitness} = export_dataset("replay-tamper")

    [example] =
      fitness |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

    tampered =
      put_in(example, ["fitness", "label"], "negative") |> put_in(["fitness", "score"], 0.0)

    File.write!(fitness, Jason.encode!(tampered) <> "\n")

    assert {:ok, report} = FitnessReplay.replay(fitness)
    assert report.score_mismatch_count == 1
    assert report.label_mismatch_count == 1
  end

  defp export_dataset(name) do
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
