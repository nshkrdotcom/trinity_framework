defmodule TrinityFrameworkDocsTest do
  use ExUnit.Case, async: true

  @required_docs ~w(
    README.md
    guides/onboarding.md
    guides/current_direction.md
    guides/system_architecture.md
    guides/crucible_path.md
    guides/service_buildout.md
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
    docs/agent_slot_provider_mapping.md
    docs/bumblebee_unpin_playbook.md
    docs/configurable_provider_pools.md
    docs/coordination_head_variants.md
    docs/elixir_svd_decomposition.md
    docs/production_qwen_slm_profile.md
    docs/production_runbook.md
    docs/provider_smoke_tests.md
    docs/sakana_adapted_artifact_plan.md
    docs/sakana_svd_byte_match_rigor_plan.md
    docs/sakana_svd_parity_debug_checklist.md
    docs/trace_persistence.md
  )

  @expected_tasks ~w(
    trinity.artifact.fetch
    trinity.crucible.inspect
    trinity.crucible.matrix_eval
    trinity.demo
    trinity.env.check
    trinity.eval
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

  @required_topics [
    {"artifact fetch", ["mix trinity.artifact.fetch", "artifact_pin.json"]},
    {"safetensors export", ["mix trinity.sakana.export_adapted", "safetensors"]},
    {"python import", ["mix trinity.sakana.import_python", "Python semantic"]},
    {"huggingface upload", ["HfHub.Repo.create", "HfHub.Commit.upload_folder"]},
    {"qwen eval", ["qwen_router_prompt_eval", "37-case"]},
    {"crucible path",
     [
       "mix trinity.crucible.matrix_eval",
       "mix trinity.eval qwen_router_prompt_eval --via crucible"
     ]},
    {"runtime profiles", ["mock_tiny", "cuda_exla"]},
    {"parity", ["mix trinity.parity.check", "mix trinity.sakana.parity_sample"]},
    {"troubleshooting", ["Troubleshooting", "Root `mix test` Says There Are No Tests"]},
    {"quality gates", ["mix ci", "mix credo --strict", "mix dialyzer --format short"]}
  ]

  test "required README and guide inventory exists" do
    for path <- @required_docs do
      assert File.regular?(path), "missing required documentation file: #{path}"
      assert String.trim(File.read!(path)) != "", "empty documentation file: #{path}"
    end
  end

  test "README and guides document the complete old coordinator command surface" do
    corpus = docs_corpus()

    missing =
      @expected_tasks
      |> Enum.reject(&String.contains?(corpus, &1))

    assert missing == []
  end

  test "README and guides cover operator flows needed for fresh-clone ownership" do
    corpus = docs_corpus()

    missing =
      for {topic, required_strings} <- @required_topics,
          required_string <- required_strings,
          not String.contains?(corpus, required_string),
          do: {topic, required_string}

    assert missing == []
  end

  test "docs keep trinity_framework as owner and trinity_coordinator as deprecated shim" do
    corpus = docs_corpus()

    assert String.contains?(corpus, "trinity_framework` is the new source-of-truth")
    assert String.contains?(corpus, "deprecated compatibility shim")
    assert String.contains?(corpus, "to-be-deprecated monolith hook")

    forbidden_strings = [
      "git clone https://github.com/nshkrdotcom/trinity_coordinator",
      "cd trinity_coordinator",
      "trinity_coordinator` is the new source-of-truth",
      "trinity_coordinator` owns new runtime behavior",
      "trinity_coordinator` is the root aggregate"
    ]

    offenders =
      for forbidden <- forbidden_strings,
          String.contains?(corpus, forbidden),
          do: forbidden

    assert offenders == []
  end

  defp docs_corpus do
    @required_docs
    |> Enum.map_join("\n\n", &File.read!/1)
  end
end
