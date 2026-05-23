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
      Trinity.SingleNode,
      Trinity.Bridge.SelfHostedInference,
      Trinity.Bridge.Inference,
      Trinity.Bridge.Trace,
      Trinity.SakanaPipeline.Exporter,
      Trinity.Ops.CommandSpec
    ]

    assert Enum.all?(modules, &Code.ensure_loaded?/1)

    assert Trinity.Ops.CommandSpec.all()
           |> Map.values()
           |> Enum.map(& &1.task)
           |> Enum.sort() == Enum.sort(@expected_tasks)
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
end
