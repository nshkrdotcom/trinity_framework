defmodule Trinity.Sakana.FitnessExampleTest do
  use ExUnit.Case, async: true

  alias Trinity.Sakana.FitnessExample

  test "builds a schema-versioned fitness example" do
    example =
      FitnessExample.new!(
        example_id: "fitness:example:1",
        source: %{"kind" => "orchestrator"},
        input: %{"transcript_hash" => "abc"},
        route: %{"route_hash" => "route-1"},
        outcome: %{"verifier_status" => "accepted"},
        fitness: %{"score" => 0.8, "label" => "positive"},
        provenance: %{"trace_path" => "trace.jsonl"}
      )

    assert example.schema_version == FitnessExample.schema_version()
    assert example.example_id == "fitness:example:1"
    assert FitnessExample.to_map(example).fitness["label"] == "positive"
  end

  test "rejects missing required maps" do
    assert {:error, {:invalid_field, :route}} =
             FitnessExample.new(
               example_id: "fitness:example:1",
               source: %{},
               input: %{},
               route: nil,
               outcome: %{},
               fitness: %{},
               provenance: %{}
             )
  end
end
