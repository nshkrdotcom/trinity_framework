defmodule TrinityFrameworkRootTest do
  use ExUnit.Case, async: true

  alias Trinity.Ops.CommandSpec

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
      CommandSpec
    ]

    assert Enum.all?(modules, &Code.ensure_loaded?/1)

    assert CommandSpec.all()
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

  test "operator command parser accepts representative old command flags at root" do
    samples = [
      {:trinity_artifact_fetch,
       ["--pin", "priv/sakana_trinity/artifact_pin.json", "--dest", "tmp/bundle", "--offline"]},
      {:trinity_demo, route_demo_args()},
      {:trinity_env_check,
       ["--artifact-dir", "priv/sakana_trinity/adapted", "--require", "cuda"]},
      {:trinity_gates, ["--fast", "--summary-out", "tmp/gates.json"]},
      {:trinity_hitl_adapted,
       ["--artifact-dir", "priv/sakana_trinity/adapted", "--runtime-profile", "mock_tiny"]},
      {:trinity_hitl_base_qwen, []},
      {:trinity_hitl_gpu, []},
      {:trinity_hitl_head_route, []},
      {:trinity_hitl_mock_loop,
       ["--runtime-profile", "mock_tiny", "--max-turns", "1", "--trace-out", "tmp/mock.jsonl"]},
      {:trinity_hitl_vector, []},
      {:trinity_parity_check,
       [
         "--python-report",
         "tmp/python.json",
         "--elixir-report",
         "tmp/elixir.json",
         "--strict-stage-tolerances",
         "--top-diffs",
         "5"
       ]},
      {:trinity_route_demo, route_demo_args()},
      {:trinity_sakana_export_adapted,
       [
         "--out",
         "tmp/export",
         "--only-index",
         "1",
         "--force",
         "--json",
         "--runtime-profile",
         "mock_tiny"
       ]},
      {:trinity_sakana_import_python,
       [
         "--source-dir",
         "tmp/python",
         "--manifest",
         "tmp/manifest.json",
         "--out",
         "tmp/import",
         "--json"
       ]},
      {:trinity_sakana_large_tensor_chunks,
       ["--python-report", "tmp/python.json", "--chunk-rows", "2048", "--no-cuda"]},
      {:trinity_sakana_parity_sample,
       [
         "--python-report",
         "tmp/python.json",
         "--semantic-only",
         "--no-cuda",
         "--out",
         "tmp/parity.json"
       ]},
      {:trinity_sakana_router_trace,
       [
         "--runtime-profile",
         "mock_tiny",
         "--python-report",
         "tmp/python.json",
         "--hidden-max-abs",
         "0.001",
         "--logits-min-cosine",
         "0.99"
       ]}
    ]

    for {task_key, args} <- samples do
      assert is_list(CommandSpec.parse!(task_key, args))
    end

    assert_raise ArgumentError, fn ->
      CommandSpec.parse!(:trinity_route_demo, ["--unknown"])
    end
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
      |> Enum.reject(fn path ->
        String.contains?(path, "/deps/") or String.contains?(path, "/_build/")
      end)

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

  defp route_demo_args do
    [
      "--mock-provider",
      "--runtime-profile",
      "mock_tiny",
      "--max-turns",
      "1",
      "--trace-out",
      "tmp/route.jsonl",
      "--governed-provider",
      "openai",
      "--governed-model",
      "gpt-4.1-mini"
    ]
  end

  defp json!(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end

  defp sha256?(value) when is_binary(value), do: value =~ ~r/\A[0-9a-f]{64}\z/
  defp sha256?(_value), do: false
end
