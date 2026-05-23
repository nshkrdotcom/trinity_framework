defmodule TrinityFrameworkRootTest do
  use ExUnit.Case, async: true

  @expected_tasks ~w(
    trinity.artifact.fetch
    trinity.demo
    trinity.env.check
    trinity.gates
    trinity.hitl.adapted
    trinity.hitl.base_qwen
    trinity.hitl.gpu
    trinity.hitl.head_route
    trinity.hitl.mock_loop
    trinity.hitl.vector
    trinity.parity.check
    trinity.route.demo
    trinity.sakana.export_adapted
    trinity.sakana.import_python
    trinity.sakana.large_tensor_chunks
    trinity.sakana.parity_sample
    trinity.sakana.router_trace
  )

  @expected_guides ~w(
    guides/onboarding.md
    guides/system_architecture.md
    guides/operations_qc.md
    guides/artifact_distribution.md
    guides/artifacts_and_export.md
    guides/runtime_profiles.md
    guides/evals.md
    guides/python_parity_reconstruction.md
    guides/stage_checks_and_tolerances.md
    guides/svd_generation_runbook.md
    guides/provider_service_hardening.md
    guides/troubleshooting.md
  )

  test "root facade compiles config, routes, and starts sessions" do
    config = Trinity.compile_config!(sample_config())

    assert {:ok, decision} =
             Trinity.route(config, %{
               coordination_run_ref: "coordination-run:root-test",
               preferred_role_ref: "role:planner",
               trace_ref: "trace:root-test"
             })

    assert decision.router_decision_ref ==
             "router_decision:coordination-run:root-test:role:planner"

    assert decision.selected_role_ref == "role:planner"
    assert decision.confidence_band == :high
    assert decision.trace_ref == "trace:root-test"

    assert {:ok, session} =
             Trinity.start_session(%{
               session_ref: "session:root-test",
               coordination_run_ref: "coordination-run:root-test",
               router_artifact_ref: "router-artifact:root-test",
               role_pack_refs: ["role:planner"]
             })

    assert session.persistence_profile_ref.profile == :memory_ephemeral
  end

  test "root aggregate exposes the runtime, bridges, pipeline, and operator command surface" do
    modules = [
      Trinity.Contracts,
      Trinity.CoordinatorCore,
      Trinity.SakanaContracts,
      Trinity.SakanaPipeline,
      Trinity.SingleNode,
      Trinity.Bridge.SelfHostedInference,
      Trinity.Bridge.Inference,
      Trinity.Bridge.Trace,
      Trinity.Ops,
      Trinity.Examples.QwenRouterPromptEval,
      Trinity.SakanaPipeline.Exporter,
      Trinity.Ops.CommandSpec
    ]

    assert Enum.all?(modules, &Code.ensure_loaded?/1)

    assert Trinity.Ops.CommandSpec.all()
           |> Map.values()
           |> Enum.map(& &1.task)
           |> Enum.sort() == Enum.sort(@expected_tasks)
  end

  test "root aggregate loads representative package modules from every architecture layer" do
    modules = [
      # Core contracts.
      Trinity.Config,
      Trinity.Router,
      Trinity.RouterArtifact,
      Trinity.RolePack,
      Trinity.ProviderPool,
      Trinity.Verifier,
      Trinity.Trace,
      Trinity.Session,
      Trinity.Artifact,
      Trinity.Runtime,
      # Coordinator core.
      Trinity.Coordinator.Orchestrator,
      Trinity.Coordinator.RoleInjector,
      Trinity.Coordinator.RunGovernance,
      Trinity.Coordinator.StateManager,
      Trinity.Coordinator.Verifier,
      Trinity.Coordinator.RouteDecisionDerivation,
      # Sakana contracts and pipeline.
      Trinity.Sakana.Manifest,
      Trinity.Sakana.RouterHeadSpec,
      Trinity.Sakana.SnapshotFixture,
      Trinity.SakanaPipeline.ArtifactIO,
      Trinity.SakanaPipeline.Exporter,
      Trinity.SakanaPipeline.PythonImporter,
      Trinity.SakanaPipeline.LargeTensorChunks,
      # Bridges and app runtime.
      Trinity.Bridge.Inference.AgentCaller,
      Trinity.Bridge.Inference.ProviderPool,
      Trinity.Bridge.SelfHostedInference.RuntimeAdapter,
      Trinity.Bridge.Trace.JSONL,
      Trinity.Bridge.Trace.JsonlSink,
      Trinity.SingleNode.Config,
      Trinity.SingleNode.RuntimeSupervisor,
      Trinity.SingleNode.Application,
      # Operator and eval packages.
      Trinity.Ops.Tasks,
      Trinity.Ops.Gates,
      Trinity.Ops.NativeTasks,
      Trinity.Examples.QwenRouterPromptEval.SnapshotResolver
    ]

    assert Enum.all?(modules, &Code.ensure_loaded?/1)
  end

  test "artifact pin keeps the published adapted bundle shape intact" do
    pin = json!("priv/sakana_trinity/artifact_pin.json")
    files = Map.fetch!(pin, "files")

    assert pin["version"] == 1
    assert pin["repo_id"] == "nshkrdotcom/trinity-coordinator-adapted-qwen3-0.6b"
    assert pin["revision"] == "v1.0.0"
    assert sha256?(pin["manifest_sha256"])
    assert length(files) == 11

    paths = Enum.map(files, &Map.fetch!(&1, "path"))

    assert "manifest.json" in paths
    assert "router_head.safetensors" in paths
    assert "checkpoints/0001_embedder.token_embedding.kernel.safetensors" in paths
    assert "checkpoints/0009_language_modeling_head.output.kernel.safetensors" in paths
    assert Enum.all?(files, &sha256?(&1["sha256"]))
  end

  test "qwen router eval fixtures keep the 37-case acceptance shape" do
    cases_fixture =
      json!("examples/qwen_router_prompt_eval/fixtures/qwen_router_prompt_eval_cases.json")

    snapshot_fixture =
      json!("examples/qwen_router_prompt_eval/fixtures/qwen_router_prompt_eval_logits.json")

    cases = Map.fetch!(cases_fixture, "cases")
    snapshots = Map.fetch!(snapshot_fixture, "cases")

    assert cases_fixture["schema_version"] == 1
    assert snapshot_fixture["schema_version"] == 1
    assert length(cases) == 37
    assert length(snapshots) == 37

    case_ids = Enum.map(cases, &Map.fetch!(&1, "id"))
    snapshot_ids = Enum.map(snapshots, &Map.fetch!(&1, "id"))

    assert Enum.uniq(case_ids) == case_ids
    assert Enum.sort(snapshot_ids) == Enum.sort(case_ids)

    assert Enum.all?(cases, fn case ->
             expected = Map.fetch!(case, "expected")
             is_integer(expected["agent_id"]) and is_integer(expected["role_id"])
           end)

    assert Enum.all?(snapshots, fn snapshot ->
             is_integer(snapshot["agent_id"]) and is_integer(snapshot["role_id"]) and
               is_integer(snapshot["token_count"]) and sha256?(snapshot["route_hash"]) and
               sha256?(snapshot["transcript_hash"])
           end)
  end

  test "root docs publish the README and every architecture guide" do
    extras =
      TrinityFramework.MixProject.project()
      |> Keyword.fetch!(:docs)
      |> Keyword.fetch!(:extras)

    assert "README.md" in extras

    for guide <- @expected_guides do
      assert guide in extras
      assert File.regular?(guide)
    end
  end

  test "root framework source does not keep hard-coded coordinator implementation paths" do
    source_files =
      Path.wildcard("{lib,core,bridges,apps,tools,examples}/**/*.{ex,exs}")
      |> Enum.reject(&String.contains?(&1, "/deps/"))
      |> Enum.reject(&String.contains?(&1, "/_build/"))

    forbidden_patterns = [
      "/home/home/p/g/n/trinity_coordinator",
      "../trinity_coordinator",
      "test/trinity_coordinator"
    ]

    offenders =
      for file <- source_files,
          source = File.read!(file),
          pattern <- forbidden_patterns,
          String.contains?(source, pattern),
          do: {file, pattern}

    assert offenders == []
  end

  defp sample_config do
    %{
      router_artifact: %{
        router_artifact_ref: "router-artifact:root-test",
        extractor_ref: "extractor:root-test",
        head_ref: "head:root-test",
        compatibility_ref: "compatibility:qwen3-0.6b",
        hash_ref: "sha256:root-test"
      },
      role_packs: [
        %{
          role_ref: "role:planner",
          prompt_ref: "prompt:planner",
          capability_refs: ["capability:plan"],
          allowed_model_profile_refs: ["model:mock"],
          tool_policy_ref: "tool-policy:default",
          memory_profile_ref: "memory:ephemeral",
          guardrail_profile_ref: "guardrail:default",
          verifier_profile_ref: "verifier:default",
          budget_ref: "budget:default",
          context_budget_ref: "context-budget:default",
          handoff_policy_ref: "handoff:default",
          appkit_projection_ref: "appkit:router-decision",
          gepa_target_refs: []
        }
      ],
      provider_pool: []
    }
  end

  defp json!(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end

  defp sha256?(value) when is_binary(value), do: value =~ ~r/\A[0-9a-f]{64}\z/
  defp sha256?(_value), do: false
end
