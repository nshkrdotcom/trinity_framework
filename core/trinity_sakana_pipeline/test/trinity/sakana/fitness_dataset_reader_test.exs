defmodule Trinity.Sakana.FitnessDatasetReaderTest do
  use ExUnit.Case, async: true

  alias Trinity.Sakana.FitnessDatasetReader

  test "reads valid fitness JSONL as string-key maps" do
    path =
      tmp_file(
        "reader-valid.jsonl",
        ~s({"example_id":"fitness:1","fitness":{"label":"positive"}}\n)
      )

    assert {:ok, %{records: [entry], skipped: []}} = FitnessDatasetReader.read(path)
    assert entry.record["example_id"] == "fitness:1"
  end

  test "malformed JSON fails by default and skips when requested" do
    path = tmp_file("reader-invalid.jsonl", ~s({"example_id":"fitness:1"}\nnot-json\n))

    assert {:error, {:invalid_json, ^path, 2, _reason}} = FitnessDatasetReader.read(path)

    assert {:ok, %{records: [_], skipped: [_]}} =
             FitnessDatasetReader.read(path, skip_invalid: true)
  end

  test "skip-invalid reports hash malformed lines without copying raw line content" do
    path = tmp_file("reader-secret-invalid.jsonl", ~s({"example_id":"fitness:1"}\nSECRET-TOKEN\n))

    assert {:ok, %{skipped: [skipped]}} = FitnessDatasetReader.read(path, skip_invalid: true)

    assert skipped.reason != "SECRET-TOKEN"
    refute String.contains?(skipped.reason, "SECRET-TOKEN")
    assert String.starts_with?(skipped.line_hash, "sha256:")
  end

  test "reads optional manifest" do
    path = tmp_file("reader-manifest.json", ~s({"dataset_digest":"sha256:abc"}\n))

    assert {:ok, %{"dataset_digest" => "sha256:abc"}} = FitnessDatasetReader.read_manifest(path)
    assert {:ok, nil} = FitnessDatasetReader.read_manifest(nil)
  end

  defp tmp_file(name, bytes) do
    dir = Path.join(["tmp", "test", "fitness_dataset_reader"])
    File.mkdir_p!(dir)
    path = Path.join(dir, name)
    File.write!(path, bytes)
    path
  end
end
