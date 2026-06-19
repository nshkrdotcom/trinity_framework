defmodule Trinity.Sakana.FitnessScoreTest do
  use ExUnit.Case, async: true

  alias Trinity.Sakana.{FitnessScore, MarginDefaults}

  test "v1 scores accepted outcomes with profile-floor margins deterministically" do
    floors = MarginDefaults.defaults(:cuda_exla)

    result =
      FitnessScore.score_v1(%{
        verifier_status: :accepted,
        agent_margin: floors.agent * 16,
        role_margin: floors.role * 16,
        revision_count: 0,
        runtime_profile: :cuda_exla
      })

    assert result.score == 1.0
    assert result.label == :positive
    assert result.margin_mode == :profile_floor
    assert result.components.margin_strength == 1.0
  end

  test "v1 applies verifier, revision, latency, cost, and budget terms" do
    result =
      FitnessScore.score_v1(
        %{
          verifier_status: :revised,
          agent_margin: 0.0,
          role_margin: 0.0,
          revision_count: 2,
          runtime_profile: :mock_tiny,
          observed_latency_ms: 200,
          estimated_cost_usd: 2.0,
          budget_exceeded: true
        },
        latency_target_ms: 100,
        cost_target_usd: 1.0
      )

    assert_in_delta result.score, 0.0, 1.0e-12
    assert result.label == :negative
    assert result.components.revision == -0.2
    assert result.components.latency == -0.05
    assert result.components.cost == -0.05
    assert result.components.budget == -0.25
  end

  test "absolute margin mode is explicit and threshold labels are configurable" do
    result =
      FitnessScore.score_v1(
        %{
          verifier_status: :unknown,
          agent_margin: 0.5,
          role_margin: 0.25,
          revision_count: 0,
          runtime_profile: :custom
        },
        margin_mode: :absolute,
        margin_scale: 0.5,
        positive_threshold: 0.7,
        negative_threshold: 0.2
      )

    assert_in_delta result.score, 0.6, 1.0e-12
    assert result.label == :neutral
    assert result.components.margin_strength == 0.5
  end
end
