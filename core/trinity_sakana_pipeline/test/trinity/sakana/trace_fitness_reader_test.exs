defmodule Trinity.Sakana.TraceFitnessReaderTest do
  use ExUnit.Case, async: true

  alias Trinity.Sakana.TraceFitnessReader

  @fixtures Path.expand("../../fixtures/fitness_traces", __DIR__)

  test "streams valid JSONL with string keys" do
    assert {:ok, %{records: records, skipped: []}} =
             TraceFitnessReader.read([fixture("orchestrator_accept.jsonl")])

    assert length(records) == 5
    assert hd(records).record["event"] == "route_decision"
    refute Map.has_key?(hd(records).record, :event)
  end

  test "fails malformed JSON by default" do
    assert {:error, {:invalid_json, path, 2, _reason}} =
             TraceFitnessReader.read([fixture("malformed_line.jsonl")])

    assert path == fixture("malformed_line.jsonl")
  end

  test "reports malformed JSON when skip_invalid is enabled" do
    assert {:ok, %{records: [_valid], skipped: [skipped]}} =
             TraceFitnessReader.read([fixture("malformed_line.jsonl")], skip_invalid: true)

    assert skipped.line == 2
    assert is_binary(skipped.line_hash)
  end

  defp fixture(name), do: Path.join(@fixtures, name)
end
