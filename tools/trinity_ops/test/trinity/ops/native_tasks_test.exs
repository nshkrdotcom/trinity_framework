defmodule Trinity.Ops.NativeTasksTest do
  use ExUnit.Case, async: false

  alias Trinity.Ops.Tasks

  test "route demo runs through the framework single-node mock path" do
    trace_path = tmp_path("route_demo.jsonl")

    assert :ok =
             Tasks.run(:trinity_route_demo, [
               "--mock-provider",
               "--runtime-profile",
               "mock_tiny",
               "--max-turns",
               "1",
               "--trace-out",
               trace_path
             ])

    assert trace_events(trace_path) |> Enum.member?("route_selected")
    assert trace_events(trace_path) |> Enum.member?("provider_called")
  end

  test "mock loop emits the route trace events" do
    trace_path = tmp_path("mock_loop.jsonl")

    assert :ok =
             Tasks.run(:trinity_hitl_mock_loop, [
               "--runtime-profile",
               "mock_tiny",
               "--max-turns",
               "1",
               "--trace-out",
               trace_path
             ])

    assert trace_events(trace_path) |> Enum.member?("slm_extracted")
    assert trace_events(trace_path) |> Enum.member?("route_selected")
    assert trace_events(trace_path) |> Enum.member?("provider_called")
  end

  test "crucible matrix eval writes strict route report" do
    out = tmp_path("crucible_matrix.json")

    assert :ok =
             Tasks.run(:trinity_crucible_matrix_eval, [
               "--runtime-profile",
               "mock_tiny",
               "--max-cases",
               "2",
               "--out",
               out
             ])

    report = Jason.decode!(File.read!(out))
    assert report["accepted?"] == true
    assert get_in(report, ["metadata", "runtime_profile"]) == "mock_tiny"
    assert get_in(report, ["metadata", "eval_mode"]) == "mock_tiny contract eval"
    assert get_in(report, ["metadata", "qwen_loaded?"]) == false
    assert get_in(report, ["metadata", "qwen_artifact_ready?"]) == false
    assert get_in(report, ["metadata", "qwen_runtime_loaded?"]) == false
    assert get_in(report, ["metadata", "qwen_route_executed?"]) == false
    assert get_in(report, ["metadata", "acceptance_level"]) =~ "does not load Qwen"
    assert get_in(report, ["metrics", "contract_strictness"]) == 1.0
    assert Enum.all?(report["rows"], &(&1["trace_signal_count"] > 0))
  end

  test "trinity eval routes qwen eval through Crucible matrix eval" do
    out = tmp_path("crucible_eval.json")

    assert :ok =
             Tasks.run(:trinity_eval, [
               "qwen_router_prompt_eval",
               "--runtime-profile",
               "mock_tiny",
               "--max-cases",
               "2",
               "--out",
               out
             ])

    assert %{"accepted?" => true, "metadata" => metadata} = Jason.decode!(File.read!(out))
    assert metadata["runtime_profile"] == "mock_tiny"
    assert metadata["eval_mode"] == "mock_tiny contract eval"
    assert metadata["qwen_loaded?"] == false
    assert metadata["qwen_artifact_ready?"] == false
    assert metadata["qwen_runtime_loaded?"] == false
    assert metadata["qwen_route_executed?"] == false
  end

  test "crucible inspect replays a pinned fixture trace without live provider" do
    trace_path = Path.join(__DIR__, "../../fixtures/crucible_minimal_forward_trace.jsonl")
    out = tmp_path("crucible_inspect_trace.json")
    root = tmp_path("crucible_v5")

    assert :ok =
             Tasks.run(:trinity_crucible_inspect, [
               "--trace",
               trace_path,
               "--artifact-root",
               root,
               "--out",
               out
             ])

    report = Jason.decode!(File.read!(out))
    assert report["mode"] == "trace"
    assert report["model_id"] == "model:fixture"
    assert report["provider_kind"] == "mock_fixture"
    assert is_list(report["evidence"])
    assert File.regular?(get_in(report, ["artifact_paths", "policy_decision_path"]))
    assert File.regular?(get_in(report, ["artifact_paths", "route_decision_path"]))
  end

  test "crucible inspect writes a report and trace" do
    out = tmp_path("crucible_inspect.json")
    trace = tmp_path("crucible_inspect.jsonl")

    assert :ok =
             Tasks.run(:trinity_crucible_inspect, [
               "--runtime-profile",
               "mock_tiny",
               "--message",
               "Inspect this route",
               "--out",
               out,
               "--trace-out",
               trace
             ])

    report = Jason.decode!(File.read!(out))
    assert get_in(report, ["crucible_trace", "trace_id"]) == "trinity-crucible-inspect"
    assert trace_events(trace) |> Enum.member?("crucible_forward_trace")
  end

  test "crucible capabilities summarizes a fixture trace without live provider" do
    trace_path = Path.join(__DIR__, "../../fixtures/crucible_minimal_forward_trace.jsonl")
    out = tmp_path("crucible_capabilities.json")

    assert :ok =
             Tasks.run(:trinity_crucible_capabilities, [
               "--trace",
               trace_path,
               "--out",
               out
             ])

    report = Jason.decode!(File.read!(out))
    assert report["schema"] == "trinity.crucible.capabilities.v1"
    assert report["trace_id"] == "trace-fixture-minimal"
    assert get_in(report, ["signals", "by_type", "final_logits"]) == 1
    assert report["requires_live_provider?"] == false
  end

  test "crucible replay validates and replays a fixture trace through policy artifacts" do
    trace_path = Path.join(__DIR__, "../../fixtures/crucible_minimal_forward_trace.jsonl")
    root = tmp_path("crucible_v5")
    out = tmp_path("crucible_replay.json")

    assert :ok =
             Tasks.run(:trinity_crucible_replay, [
               "--trace",
               trace_path,
               "--artifact-root",
               root,
               "--out",
               out
             ])

    report = Jason.decode!(File.read!(out))
    assert report["schema"] == "trinity.crucible.replay.v1"
    assert report["trace_id"] == "trace-fixture-minimal"
    assert get_in(report, ["validation", "shape"]) == "ok"
    assert is_binary(get_in(report, ["route_decision", "assigned_role"]))
    assert File.regular?(get_in(report, ["artifact_paths", "policy_decision_path"]))
    assert File.regular?(get_in(report, ["artifact_paths", "route_decision_path"]))
  end

  test "live Crucible runtime calls use negotiated tap plans" do
    source = File.read!("tools/trinity_ops/lib/trinity/ops/native_tasks.ex")

    refute String.contains?(source, "CrucibleRuntime.forward(pid, nil")
    refute String.contains?(source, "CrucibleRuntime.forward(pid,\n          nil")
  end

  test "crucible trace matrix expands directories and writes decision artifacts" do
    root = tmp_path("crucible_v5")
    trace_dir = tmp_path("trace_dir")
    nested_dir = Path.join(trace_dir, "native")
    out = tmp_path("matrix_traces.json")
    source = Path.expand("../../../../../runs/synthetic_python_gpt2_trace.jsonl", __DIR__)
    trace_path = Path.join(nested_dir, "synthetic_python_gpt2_trace.jsonl")

    File.mkdir_p!(nested_dir)
    File.cp!(source, trace_path)

    assert :ok =
             Tasks.run(:trinity_crucible_matrix_eval, [
               "--trace",
               trace_dir,
               "--artifact-root",
               root,
               "--out",
               out
             ])

    assert %{"rows" => [row]} = Jason.decode!(File.read!(out))
    assert row["trace_path"] == trace_path
    assert row["provider_kind"] == "python_pytorch"
    assert File.regular?(get_in(row, ["artifact_paths", "policy_decision_path"]))
    assert File.regular?(get_in(row, ["artifact_paths", "route_decision_path"]))
  end

  test "artifact fetch uses the framework registry pin fetcher" do
    content = ~s({"artifact":"ok"}\n)
    sha256 = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
    pin_path = tmp_path("artifact_pin.json")
    dest = tmp_path("artifact")

    File.write!(
      pin_path,
      Jason.encode!(%{
        version: 1,
        repo_id: "example/trinity",
        revision: "test",
        manifest_sha256: sha256,
        files: [%{path: "manifest.json", sha256: sha256}]
      })
    )

    Process.put(:trinity_artifact_fetch_downloader, fn args ->
      cache_path = Keyword.fetch!(args, :cache_path)
      File.mkdir_p!(Path.dirname(cache_path))
      File.write!(cache_path, content)
      {:ok, cache_path}
    end)

    on_exit(fn -> Process.delete(:trinity_artifact_fetch_downloader) end)

    assert :ok =
             Tasks.run(:trinity_artifact_fetch, [
               "--pin",
               pin_path,
               "--dest",
               dest
             ])

    assert File.read!(Path.join(dest, "manifest.json")) == content
  end

  test "artifact fetch default downloader reads the Hugging Face offline cache" do
    content = ~s({"artifact":"cached"}\n)
    sha256 = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
    pin_path = tmp_path("cached_artifact_pin.json")
    dest = tmp_path("cached_artifact")
    cache_dir = tmp_path("hf_cache")
    repo_id = "example/trinity"
    revision = "test-revision"

    previous_cache_dir = Application.get_env(:hf_hub, :cache_dir)
    Application.put_env(:hf_hub, :cache_dir, cache_dir)

    on_exit(fn ->
      restore_hf_cache_dir(previous_cache_dir)
    end)

    cached_path = HfHub.FS.file_path(repo_id, :dataset, "manifest.json", revision)
    File.mkdir_p!(Path.dirname(cached_path))
    File.write!(cached_path, content)

    File.write!(
      pin_path,
      Jason.encode!(%{
        version: 1,
        repo_id: repo_id,
        revision: revision,
        manifest_sha256: sha256,
        files: [%{path: "manifest.json", sha256: sha256}]
      })
    )

    assert :ok =
             Tasks.run(:trinity_artifact_fetch, [
               "--pin",
               pin_path,
               "--dest",
               dest,
               "--offline"
             ])

    assert File.read!(Path.join(dest, "manifest.json")) == content
  end

  test "crucible transcript captures output and artifact index row" do
    root = tmp_path("crucible_v5")
    executable = System.find_executable("elixir") || "elixir"

    assert :ok =
             Tasks.run(:trinity_crucible_transcript, [
               "--name",
               "transcript smoke",
               "--artifact-root",
               root,
               "--phase",
               "2",
               "--",
               executable,
               "-e",
               "IO.puts(\"transcript ok\")"
             ])

    transcript_path = Path.join([root, "transcripts", "transcript_smoke.log"])
    index_path = Path.join(root, "ARTIFACT_INDEX.md")

    assert File.read!(transcript_path) =~ "transcript ok"
    assert File.read!(index_path) =~ "| 2 | #{executable} -e IO.puts"
  end

  test "crucible transcript artifact names use collapsed fixed-character sanitizing" do
    root = tmp_path("crucible_v5_sanitized")
    executable = System.find_executable("true") || System.find_executable("elixir")

    cases = [
      {"abc", "abc.log"},
      {"a b", "a_b.log"},
      {"a///b", "a_b.log"},
      {"é/🔥", "command.log"},
      {"../../path", ".._.._path.log"},
      {"", "command.log"}
    ]

    for {name, expected_file} <- cases do
      assert :ok =
               Tasks.run(:trinity_crucible_transcript, [
                 "--name",
                 name,
                 "--artifact-root",
                 root,
                 "--",
                 executable
               ])

      assert File.regular?(Path.join([root, "transcripts", expected_file]))
    end
  end

  test "parity check performs strict stage checks without the Python wrapper" do
    python_path = tmp_path("python_report.json")
    elixir_path = tmp_path("elixir_report.json")
    summary_path = tmp_path("summary.json")
    digest = String.duplicate("a", 64)

    File.write!(
      python_path,
      Jason.encode!(%{
        reference: %{
          expected_bf16_sha256: digest,
          current_python_baseline_label: "python",
          current_python_baseline_bf16_sha256: digest,
          expected_hash_reproducible: true
        },
        variants: [%{label: "python", observed_bf16_sha256: digest}]
      })
    )

    File.write!(
      elixir_path,
      Jason.encode!(%{
        reference: %{expected_bf16_sha256: digest},
        semantic_python_component_variants: [
          %{
            label: "elixir",
            observed_bf16_sha256: digest,
            stage_debug: %{
              checks: [
                %{
                  stage: "stage.final_bf16",
                  required_for_functional_parity: true,
                  functional_passed: true
                }
              ]
            }
          }
        ]
      })
    )

    assert :ok =
             Tasks.run(:trinity_parity_check, [
               "--python-report",
               python_path,
               "--elixir-report",
               elixir_path,
               "--summary-out",
               summary_path
             ])

    assert %{"ok" => true} = Jason.decode!(File.read!(summary_path))
  end

  test "large tensor chunks writes a bounded semantic chunk report" do
    python_path = tmp_path("large_python_report.json")
    out = tmp_path("large_chunks.json")

    File.write!(
      python_path,
      Jason.encode!(%{
        selected_tensors: [
          %{
            source_name: "model.embed_tokens.weight",
            shape: [2048, 1024]
          }
        ]
      })
    )

    assert :ok =
             Tasks.run(:trinity_sakana_large_tensor_chunks, [
               "--python-report",
               python_path,
               "--out",
               out,
               "--chunk-rows",
               "1024",
               "--no-cuda"
             ])

    assert %{"summary" => %{"chunk_count" => 2}} = Jason.decode!(File.read!(out))
  end

  test "large tensor chunks defaults to the canonical Python reference manifest" do
    out = tmp_path("default_large_chunks.json")

    assert :ok =
             Tasks.run(:trinity_sakana_large_tensor_chunks, [
               "--out",
               out,
               "--no-cuda"
             ])

    report = Jason.decode!(File.read!(out))
    assert report["inputs"]["python_report"] =~ "sakana_python_reference_manifest.json"
    assert is_integer(report["summary"]["chunk_count"])
  end

  defp trace_events(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(fn line -> line |> Jason.decode!() |> Map.fetch!("event") end)
  end

  defp tmp_path(name) do
    root = Path.join(System.tmp_dir!(), "trinity_ops_native_tasks_test")
    File.mkdir_p!(root)
    Path.join(root, "#{System.unique_integer([:positive])}_#{name}")
  end

  defp restore_hf_cache_dir(nil), do: Application.delete_env(:hf_hub, :cache_dir)
  defp restore_hf_cache_dir(value), do: Application.put_env(:hf_hub, :cache_dir, value)
end
