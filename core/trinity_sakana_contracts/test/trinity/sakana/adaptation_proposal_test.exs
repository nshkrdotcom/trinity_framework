defmodule Trinity.Sakana.AdaptationProposalTest do
  use ExUnit.Case, async: true

  alias Trinity.Sakana.AdaptationProposal

  test "builds a valid adaptation proposal" do
    proposal =
      AdaptationProposal.new!(
        proposal_id: "proposal:sha256:abc",
        dataset_digest: "sha256:data",
        candidate_digest: "sha256:candidate",
        baseline_summary: %{},
        candidate_summary: %{},
        route_deltas: [],
        score_delta_summary: %{},
        regressions: [],
        vector_preflight: nil,
        verdict: "shadow_ready",
        status_reason: nil
      )

    assert proposal.schema_version == AdaptationProposal.schema_version()
    assert "artifact_gate_ready" in AdaptationProposal.verdicts()
  end

  test "rejects unknown verdicts" do
    assert {:error, {:invalid_verdict, "ship_it"}} =
             AdaptationProposal.new(
               proposal_id: "proposal:sha256:abc",
               dataset_digest: "sha256:data",
               candidate_digest: "sha256:candidate",
               baseline_summary: %{},
               candidate_summary: %{},
               route_deltas: [],
               score_delta_summary: %{},
               regressions: [],
               vector_preflight: nil,
               verdict: "ship_it",
               status_reason: nil
             )
  end
end
