defmodule TrinityFrameworkDocsTest do
  use ExUnit.Case, async: true

  @required_docs ~w(
    README.md
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

  @required_topics [
    {"artifact fetch", ["mix trinity.artifact.fetch", "artifact_pin.json"]},
    {"safetensors export", ["mix trinity.sakana.export_adapted", "safetensors"]},
    {"python import", ["mix trinity.sakana.import_python", "Python semantic"]},
    {"huggingface upload", ["HfHub.Repo.create", "HfHub.Commit.upload_folder"]},
    {"qwen eval", ["qwen_router_prompt_eval", "37-case"]},
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

    forbidden_patterns = [
      ~r/git clone\s+https:\/\/github\.com\/nshkrdotcom\/trinity_coordinator/,
      ~r/\bcd\s+trinity_coordinator\b/,
      ~r/trinity_coordinator`\s+is the new source-of-truth/,
      ~r/trinity_coordinator`\s+owns new runtime behavior/,
      ~r/trinity_coordinator`\s+is the root aggregate/
    ]

    offenders =
      for pattern <- forbidden_patterns,
          Regex.match?(pattern, corpus),
          do: Regex.source(pattern)

    assert offenders == []
  end

  defp docs_corpus do
    @required_docs
    |> Enum.map_join("\n\n", &File.read!/1)
  end
end
