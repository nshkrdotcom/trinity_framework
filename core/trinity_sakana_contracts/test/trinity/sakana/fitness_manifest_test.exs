defmodule Trinity.Sakana.FitnessManifestTest do
  use ExUnit.Case, async: true

  alias Trinity.Sakana.FitnessManifest

  test "builds a complete dataset manifest" do
    manifest =
      FitnessManifest.new!(
        generated_at: "2026-06-18T00:00:00Z",
        source_trace_paths: ["trace.jsonl"],
        record_count: 2,
        positive_count: 1,
        neutral_count: 1,
        negative_count: 0,
        skipped_count: 0,
        conflict_count: 0,
        score_formula: "v1",
        score_formula_version: 1,
        margin_mode: "profile_floor",
        content_mode: "hash",
        redaction_mode: "allowlist",
        provenance_summary: %{},
        artifact_refs: ["artifact:fixture"],
        runtime_profiles: ["mock_tiny"],
        route_hashes_digest: "sha256:routes",
        dataset_digest: "sha256:dataset"
      )

    assert manifest.schema_version == FitnessManifest.schema_version()
    assert FitnessManifest.to_map(manifest).record_count == 2
  end

  test "rejects inconsistent label counts" do
    assert {:error, :inconsistent_label_counts} =
             FitnessManifest.new(
               generated_at: "2026-06-18T00:00:00Z",
               source_trace_paths: [],
               record_count: 1,
               positive_count: 1,
               neutral_count: 1,
               negative_count: 0,
               skipped_count: 0,
               conflict_count: 0,
               score_formula: "v1",
               score_formula_version: 1,
               margin_mode: "profile_floor",
               content_mode: "hash",
               redaction_mode: "allowlist",
               provenance_summary: %{},
               artifact_refs: [],
               runtime_profiles: [],
               route_hashes_digest: "sha256:routes",
               dataset_digest: "sha256:dataset"
             )
  end
end
