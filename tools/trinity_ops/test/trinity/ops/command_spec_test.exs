defmodule Trinity.Ops.CommandSpecTest do
  use ExUnit.Case, async: true

  alias Trinity.Ops.CommandSpec
  alias Trinity.Ops.Gates

  @expected_tasks ~w(
    trinity.artifact.fetch
    trinity.crucible.inspect
    trinity.crucible.matrix_eval
    trinity.crucible.transcript
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

  @sample_args %{
    trinity_artifact_fetch: ["--pin", "pin.json", "--dest", "artifact", "--offline"],
    trinity_crucible_inspect: ["--runtime-profile", "mock_tiny", "--message", "hello"],
    trinity_crucible_matrix_eval: [
      "--runtime-profile",
      "mock_tiny",
      "--max-cases",
      "2",
      "--artifact-root",
      "tmp/crucible_v5"
    ],
    trinity_crucible_transcript: [
      "--name",
      "sample",
      "--cwd",
      ".",
      "--artifact-root",
      "tmp/crucible_v5",
      "--phase",
      "2",
      "--",
      "elixir",
      "-e",
      "IO.puts(:ok)"
    ],
    trinity_demo: [],
    trinity_env_check: ["-a", "artifact", "-r", "cuda"],
    trinity_eval: ["qwen_router_prompt_eval", "--max-cases", "2"],
    trinity_gates: [
      "--summary-out",
      "tmp/gates.json",
      "--skip-docs",
      "--include-parity-check",
      "--include-hex-build",
      "--python-report",
      "python.json",
      "--elixir-report",
      "elixir.json"
    ],
    trinity_hitl_adapted: [
      "--artifact-dir",
      "artifact",
      "--runtime-profile",
      "host_exla",
      "--message",
      "hello"
    ],
    trinity_hitl_base_qwen: [],
    trinity_hitl_gpu: [],
    trinity_hitl_head_route: [],
    trinity_hitl_mock_loop: [
      "--artifact-dir",
      "artifact",
      "--runtime-profile",
      "host_exla",
      "--max-turns",
      "3",
      "--trace-out",
      "trace.jsonl"
    ],
    trinity_hitl_vector: [],
    trinity_parity_check: [
      "--python-report",
      "python.json",
      "--elixir-report",
      "elixir.json",
      "--top-diffs",
      "5"
    ],
    trinity_route_demo: [
      "--allow-live",
      "--mock-provider",
      "--message",
      "hello",
      "--trace-content",
      "hash"
    ],
    trinity_sakana_export_adapted: [
      "--force",
      "--svd-compute-type",
      "f32",
      "--out",
      "tmp/out"
    ],
    trinity_sakana_import_python: [
      "--source-dir",
      "python",
      "--out",
      "artifact",
      "--no-load-qwen",
      "--json"
    ],
    trinity_sakana_large_tensor_chunks: [
      "--python-report",
      "report.json",
      "--chunk-rows",
      "128",
      "--source",
      "embed"
    ],
    trinity_sakana_parity_sample: [
      "--python-report",
      "report.json",
      "--semantic-only",
      "--selected-source-filter",
      "layer26"
    ],
    trinity_sakana_router_trace: [
      "--artifact-dir",
      "artifact",
      "--runtime-profile",
      "cuda_exla",
      "--hidden-max-abs",
      "0.1",
      "--logits-min-cosine",
      "0.99"
    ]
  }

  test "preserves operator-visible task names" do
    assert CommandSpec.all()
           |> Map.values()
           |> Enum.map(& &1.task)
           |> Enum.sort() == Enum.sort(@expected_tasks)
  end

  test "parses every task surface" do
    Enum.each(CommandSpec.all(), fn {task_key, _spec} ->
      assert is_list(CommandSpec.parse!(task_key, Map.fetch!(@sample_args, task_key)))
    end)
  end

  test "rejects unknown task options" do
    exception =
      assert_raise ArgumentError, fn ->
        CommandSpec.parse!(:trinity_demo, ["--unknown"])
      end

    assert String.contains?(Exception.message(exception), "invalid options")
  end

  test "rejects Dialyzer skip gate option" do
    skip_prefix = "--skip-"
    analyzer_name = "dialyzer"

    exception =
      assert_raise ArgumentError, fn ->
        CommandSpec.parse!(:trinity_gates, [skip_prefix <> analyzer_name])
      end

    assert String.contains?(Exception.message(exception), "invalid options")
  end

  test "parses the trinity.gates flag surface" do
    opts =
      CommandSpec.parse!(:trinity_gates, [
        "--summary-out",
        "tmp/gates.json",
        "--skip-docs",
        "--fast",
        "--include-parity-check",
        "--include-hex-build",
        "--python-report",
        "python.json",
        "--elixir-report",
        "elixir.json"
      ])

    assert opts[:summary_out] == "tmp/gates.json"
    assert opts[:skip_docs]
    assert opts[:fast]
    assert opts[:include_parity_check]
    assert opts[:include_hex_build]
    assert opts[:python_report] == "python.json"
    assert opts[:elixir_report] == "elixir.json"
  end

  test "keeps static analysis gates in fast mode" do
    step_names =
      [fast: true, skip_docs: true]
      |> Gates.steps()
      |> Enum.map(&elem(&1, 0))

    assert :credo in step_names
    assert :dialyzer in step_names
    refute :docs in step_names
  end

  test "parses representative flags from every task batch" do
    assert CommandSpec.parse!(:trinity_env_check, ["-a", "artifact", "-r", "cuda"]) ==
             [artifact_dir: "artifact", require: "cuda"]

    assert CommandSpec.parse!(:trinity_artifact_fetch, [
             "--pin",
             "pin.json",
             "--dest",
             "artifact",
             "--offline"
           ])[:offline]

    assert CommandSpec.parse!(:trinity_route_demo, [
             "--allow-live",
             "--mock-provider",
             "--message",
             "hello",
             "--trace-content",
             "hash"
           ])[:trace_content] == "hash"

    assert CommandSpec.parse!(:trinity_eval, [
             "qwen_router_prompt_eval"
           ])[:_args] == ["qwen_router_prompt_eval"]

    assert CommandSpec.parse!(:trinity_crucible_matrix_eval, [
             "--runtime-profile",
             "mock_tiny",
             "--max-cases",
             "3",
             "--artifact-root",
             "tmp/crucible_v5",
             "--model-id",
             "gpt2",
             "--backend",
             "binary",
             "--architecture",
             "for_causal_language_modeling",
             "--stability-repeats",
             "2"
           ])[:max_cases] == 3

    assert CommandSpec.parse!(:trinity_hitl_mock_loop, [
             "--artifact-dir",
             "artifact",
             "--runtime-profile",
             "host_exla",
             "--max-turns",
             "3",
             "--trace-out",
             "trace.jsonl"
           ])[:max_turns] == 3

    assert CommandSpec.parse!(:trinity_sakana_export_adapted, [
             "--force",
             "--svd-compute-type",
             "f32",
             "--out",
             "tmp/out"
           ])[:svd_compute_type] == "f32"

    assert CommandSpec.parse!(:trinity_sakana_import_python, [
             "--source-dir",
             "python",
             "--out",
             "artifact",
             "--no-load-qwen",
             "--json"
           ])[:no_load_qwen]

    assert CommandSpec.parse!(:trinity_sakana_large_tensor_chunks, [
             "--python-report",
             "report.json",
             "--chunk-rows",
             "128",
             "--source",
             "embed"
           ])[:chunk_rows] == 128

    assert CommandSpec.parse!(:trinity_sakana_parity_sample, [
             "--python-report",
             "report.json",
             "--semantic-only",
             "--selected-source-filter",
             "layer26"
           ])[:selected_source_filter] == "layer26"

    assert CommandSpec.parse!(:trinity_sakana_router_trace, [
             "--artifact-dir",
             "artifact",
             "--runtime-profile",
             "cuda_exla",
             "--hidden-max-abs",
             "0.1",
             "--logits-min-cosine",
             "0.99"
           ])[:hidden_max_abs] == 0.1
  end
end
