defmodule Trinity.Coordinator.ReflexPolicyTest do
  use ExUnit.Case, async: true

  alias Trinity.Coordinator.{ReflexPolicy, RunGovernance}
  alias Trinity.Sakana.MarginDefaults

  test "profile-floor margins classify high, medium, and low" do
    floor = MarginDefaults.defaults(:cuda_exla)

    assert {:ok, :high} =
             ReflexPolicy.classify(route(floor.agent * 4, floor.role * 4))

    assert {:ok, :medium} =
             ReflexPolicy.classify(route(floor.agent * 2, floor.role * 2))

    assert {:ok, :low} =
             ReflexPolicy.classify(route(floor.agent / 2, floor.role * 2))

    assert {:ok, :low} =
             ReflexPolicy.classify(route(floor.agent * 2, floor.role / 2))
  end

  test "explicit low and uncertain bands force low classification" do
    assert {:ok, :low} = ReflexPolicy.classify(route(10.0, 10.0, :low))
    assert {:ok, :low} = ReflexPolicy.classify(route(10.0, 10.0, "uncertain"))
  end

  test "missing margins default medium and can be configured low" do
    missing = route(nil, nil)

    assert {:ok, :medium} = ReflexPolicy.classify(missing)

    assert {:ok, :low} =
             ReflexPolicy.classify(missing, reflex_missing_margin: :low)
  end

  test "confidence classes map to deterministic reflex actions" do
    floor = MarginDefaults.defaults(:cuda_exla)

    assert {:ok, %{action: :direct_dispatch, reason: :high_confidence}} =
             ReflexPolicy.evaluate(route(floor.agent * 4, floor.role * 4))

    assert {:ok, %{action: :normal_dispatch, reason: :medium_confidence}} =
             ReflexPolicy.evaluate(route(floor.agent * 2, floor.role * 2))

    assert {:ok,
            %{
              action: :thinker_then_verifier,
              reason: :low_margin,
              forced_sequence: [:thinker, :verifier],
              next_role_override: 1
            }} = ReflexPolicy.evaluate(route(floor.agent / 2, floor.role * 2))
  end

  test "low thinker and verifier routes derive stable next roles through role helpers" do
    assert {:ok, %{next_role_override: 2}} =
             ReflexPolicy.evaluate(route(0.0, 0.0, :low, :thinker))

    assert {:ok, %{next_role_override: nil}} =
             ReflexPolicy.evaluate(route(0.0, 0.0, :low, :verifier))
  end

  test "disabled policy preserves normal dispatch while retaining classification" do
    assert {:ok,
            %{
              enabled?: false,
              confidence_class: :low,
              action: :normal_dispatch,
              reason: :disabled,
              forced_sequence: []
            }} = ReflexPolicy.evaluate(route(0.0, 0.0), reflex_enabled?: false)
  end

  test "absolute mode uses explicit thresholds" do
    opts = [
      reflex_margin_mode: :absolute,
      reflex_high_agent_margin: 8.0,
      reflex_high_role_margin: 6.0,
      reflex_low_agent_margin: 2.0,
      reflex_low_role_margin: 1.0
    ]

    assert {:ok, :high} = ReflexPolicy.classify(route(8.0, 6.0), opts)
    assert {:ok, :medium} = ReflexPolicy.classify(route(4.0, 3.0), opts)
    assert {:ok, :low} = ReflexPolicy.classify(route(1.0, 3.0), opts)
  end

  test "explicit low thresholds can force low diagnostics above absolute defaults" do
    opts = [
      reflex_margin_mode: :absolute,
      reflex_low_agent_margin: 999.0,
      reflex_low_role_margin: 999.0
    ]

    assert {:ok, :low} = ReflexPolicy.classify(route(10.0, 10.0), opts)
  end

  test "invalid modes, thresholds, and sequences fail closed" do
    assert {:error, {:invalid_reflex_margin_mode, "unbounded-mode"}} =
             ReflexPolicy.evaluate(route(1.0, 1.0),
               reflex_margin_mode: "unbounded-mode"
             )

    assert {:error, {:invalid_reflex_threshold, :reflex_low_agent_margin, "zero"}} =
             ReflexPolicy.evaluate(route(1.0, 1.0),
               reflex_low_agent_margin: "zero"
             )

    assert {:error, {:invalid_reflex_force_sequence, [:worker]}} =
             ReflexPolicy.evaluate(route(1.0, 1.0), reflex_force_sequence: [:worker])
  end

  test "string options use fixed cases and reject unknown strings" do
    assert {:ok, :high} =
             ReflexPolicy.classify(route(10.0, 10.0),
               reflex_margin_mode: "absolute",
               reflex_high_agent_margin: 1.0,
               reflex_high_role_margin: 1.0,
               reflex_low_agent_margin: 0.1,
               reflex_low_role_margin: 0.1
             )

    for index <- 1..50 do
      value = "invalid-reflex-mode-#{index}"

      assert {:error, {:invalid_reflex_margin_mode, ^value}} =
               ReflexPolicy.evaluate(route(1.0, 1.0), reflex_margin_mode: value)
    end
  end

  test "explanation output is trace-safe and excludes source content" do
    source =
      route(0.0, 0.0)
      |> Map.put(:messages, [%{role: "user", content: "TOP SECRET"}])
      |> Map.put(:provider_payload, %{authorization: "Bearer SECRET"})

    assert {:ok, explanation} = ReflexPolicy.evaluate(source)

    encoded = inspect(explanation)
    refute String.contains?(encoded, "TOP SECRET")
    refute String.contains?(encoded, "Bearer SECRET")
    refute Map.has_key?(explanation, :messages)
    refute Map.has_key?(explanation, :provider_payload)
  end

  test "run governance materializes bounded reflex defaults and fixed string options" do
    assert {:ok, defaults} = RunGovernance.materialize_orchestrator_opts([])
    assert defaults[:reflex_enabled?]
    assert defaults[:reflex_policy] == ReflexPolicy
    assert defaults[:reflex_margin_mode] == :profile_floor
    assert defaults[:reflex_missing_margin] == :medium
    assert defaults[:reflex_force_sequence] == [:thinker, :verifier]

    assert {:ok, explicit} =
             RunGovernance.materialize_orchestrator_opts(
               reflex_enabled?: false,
               reflex_margin_mode: "absolute",
               reflex_missing_margin: "low"
             )

    refute explicit[:reflex_enabled?]
    assert explicit[:reflex_margin_mode] == :absolute
    assert explicit[:reflex_missing_margin] == :low

    assert {:error, {:invalid_reflex_policy, "unsafe-module"}} =
             RunGovernance.materialize_orchestrator_opts(reflex_policy: "unsafe-module")
  end

  defp route(agent_margin, role_margin, band \\ :medium, role_atom \\ :worker) do
    %{
      decision: %{
        margins: %{agent: agent_margin, role: role_margin},
        confidence_band: band,
        runtime_profile: :cuda_exla
      },
      role_atom: role_atom
    }
  end
end
