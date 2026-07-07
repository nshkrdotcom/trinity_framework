defmodule Trinity.Ops.NativeTasks do
  @moduledoc """
  Framework-owned implementations for the `mix trinity.*` operator tasks.

  These tasks intentionally call the deconstructed framework packages directly.
  This module must not call back into `trinity_coordinator`.
  """

  alias Crucible.Policy.PolicyPlan, as: CruciblePolicyPlan
  alias CrucibleBumblebee.Artifacts, as: CrucibleArtifacts
  alias CrucibleFactorization.SVD
  alias CrucibleModelRegistry.Pins.{ArtifactPin, Fetcher, Verifier}
  alias CrucibleSignalTrace.Ingest, as: CrucibleTraceIngest
  alias CrucibleSignalTrace.Validate, as: CrucibleTraceValidate

  alias SelfHostedInferenceBumblebee.{
    Extractor,
    HeadLoader,
    QwenSakanaLoader,
    RoutingHead,
    SLMProfile
  }

  alias SelfHostedInferenceBumblebee.Runtime.{Preflight, Profile}
  alias SelfHostedInferenceCore.CrucibleRuntime
  alias Trinity.Bridge.Trace.JsonlSink
  alias Trinity.Coordinator.TraceEvent

  alias Trinity.Crucible.{
    ArtifactPaths,
    OperatorReport,
    RequestContext,
    TapPlanBuilder,
    TraceAdapter
  }

  alias Trinity.Ops.{CommandSpec, CrucibleMechInterpTasks}
  alias Trinity.Ops.EvalMetadata
  alias Trinity.RefSanitizer
  alias Trinity.SingleNode.Config

  alias Trinity.SakanaPipeline.{
    ArtifactIO,
    Exporter,
    LargeTensorChunks,
    ParityTrace,
    PythonImporter
  }

  @default_message "Select a TRINITY role for this reasoning task."
  @default_route_trace_path "tmp/trinity_route_demo.jsonl"
  @default_mock_trace_path "tmp/trinity_mock_trace.jsonl"
  @default_large_tensor_out "tmp/sakana_parity/large_tensor_chunks/elixir_large_tensor_chunks.json"
  @default_parity_sample_out "tmp/sakana_parity/elixir_sample_trace.json"
  @default_router_trace_schema "trinity_sakana_router_trace.v1"
  @default_router_vector_tensor "trinity_router_es_vector"
  @summary_schema_version 1
  @tail_bytes 4096

  @spec run(CommandSpec.task_key(), keyword()) :: :ok
  def run(:trinity_artifact_fetch, opts), do: artifact_fetch(opts)
  def run(:trinity_crucible_capabilities, opts), do: crucible_capabilities(opts)
  def run(:trinity_crucible_capture, opts), do: CrucibleMechInterpTasks.capture(opts)

  def run(:trinity_crucible_generation_trace, opts),
    do: CrucibleMechInterpTasks.generation_trace(opts)

  def run(:trinity_crucible_inspect, opts), do: crucible_inspect(opts)
  def run(:trinity_crucible_logit_lens, opts), do: CrucibleMechInterpTasks.logit_lens(opts)
  def run(:trinity_crucible_matrix_eval, opts), do: crucible_matrix_eval(opts)
  def run(:trinity_crucible_patch, opts), do: CrucibleMechInterpTasks.patch(opts)
  def run(:trinity_crucible_replay, opts), do: crucible_replay(opts)
  def run(:trinity_crucible_trace_replay, opts), do: crucible_replay(opts)
  def run(:trinity_crucible_transcript, opts), do: crucible_transcript(opts)
  def run(:trinity_demo, opts), do: route_demo(opts)
  def run(:trinity_eval, opts), do: eval(opts)
  def run(:trinity_hitl_adapted, opts), do: hitl_adapted(opts)
  def run(:trinity_hitl_base_qwen, _opts), do: hitl_base_qwen()
  def run(:trinity_hitl_gpu, _opts), do: hitl_gpu()
  def run(:trinity_hitl_head_route, _opts), do: hitl_head_route()
  def run(:trinity_hitl_mock_loop, opts), do: hitl_mock_loop(opts)
  def run(:trinity_hitl_vector, _opts), do: hitl_vector()
  def run(:trinity_parity_check, opts), do: parity_check(opts)
  def run(:trinity_route_demo, opts), do: route_demo(opts)
  def run(:trinity_sakana_export_adapted, opts), do: sakana_export_adapted(opts)
  def run(:trinity_sakana_import_python, opts), do: sakana_import_python(opts)
  def run(:trinity_sakana_large_tensor_chunks, opts), do: sakana_large_tensor_chunks(opts)
  def run(:trinity_sakana_parity_sample, opts), do: sakana_parity_sample(opts)
  def run(:trinity_sakana_router_trace, opts), do: sakana_router_trace(opts)

  defp artifact_fetch(opts) do
    start_app!()

    pin_path = Keyword.get(opts, :pin, default_pin_path())
    destination = Keyword.get(opts, :dest, default_artifact_dir())
    offline? = Keyword.get(opts, :offline, false)
    downloader = Process.get(:trinity_artifact_fetch_downloader, &hf_hub_artifact_download/1)

    banner("TRINITY ARTIFACT FETCH")
    kv("Pin", pin_path)
    kv("Destination", destination)
    kv("Offline", offline?)

    pin = ArtifactPin.load!(pin_path)

    receipt =
      Fetcher.fetch!(pin, destination,
        downloader: downloader,
        offline_mode: offline?
      )

    verified = Verifier.verify!(pin, destination)

    kv("Fetched files", receipt.files |> Enum.count(&(&1.status == :fetched)))
    kv("Skipped files", receipt.files |> Enum.count(&(&1.status == :skipped)))
    kv("Verified files", length(verified.files))
    pass("TRINITY ARTIFACT FETCH")
  end

  defp crucible_transcript(opts) do
    command = Keyword.get(opts, :_args, [])

    if command == [] do
      Mix.raise("usage: mix trinity.crucible.transcript [opts] -- command arg...")
    end

    run_transcript_command(opts, command)
  end

  defp crucible_capabilities(opts) do
    start_app!()

    trace_path = require_regular_path!(opts, :trace)
    trace = load_v4_trace!(trace_path)

    paths =
      ArtifactPaths.new(root: v5_artifact_root(opts), trace_name: trace.trace_id)
      |> ArtifactPaths.ensure!()

    out =
      Keyword.get(opts, :out) ||
        ArtifactPaths.report_path(
          paths,
          "capabilities_#{safe_artifact_name(trace.trace_id)}.json"
        )

    payload = %{
      trace_path: trace_path,
      requires_live_provider?: false,
      trace: TraceAdapter.summarize_trace(trace),
      signals: TraceAdapter.summarize_signals(trace),
      capabilities: TraceAdapter.summarize_capabilities(trace),
      route_evidence: TraceAdapter.extract_route_evidence(trace),
      generation_evidence: TraceAdapter.extract_generation_evidence(trace),
      trajectory_evidence: TraceAdapter.extract_trajectory_evidence(trace)
    }

    report =
      OperatorReport.new!(
        schema: "trinity.crucible.capabilities.v1",
        mode: :trace,
        trace_id: trace.trace_id,
        payload: payload,
        summaries: Map.take(payload, [:trace, :signals, :capabilities]),
        artifact_paths: %{report_path: out}
      )
      |> OperatorReport.to_map()

    ArtifactIO.write_json!(out, normalize_for_json(report))
    kv("Wrote capabilities report", out)
    print_payload(report)
    pass("TRINITY CRUCIBLE CAPABILITIES")
  end

  defp crucible_replay(opts) do
    start_app!()

    trace_path = require_regular_path!(opts, :trace)
    trace = load_v4_trace!(trace_path)
    decision = CruciblePolicyPlan.evaluate(trace)

    paths =
      ArtifactPaths.new(root: v5_artifact_root(opts), trace_name: trace.trace_id)
      |> ArtifactPaths.ensure!()

    artifact_paths =
      persist_crucible_decision_artifacts(
        :replay,
        trace,
        decision,
        Keyword.put(opts, :artifact_suffix, Path.basename(trace_path))
      )

    out =
      Keyword.get(opts, :out) ||
        ArtifactPaths.report_path(paths, "replay_#{safe_artifact_name(trace.trace_id)}.json")

    payload =
      :replay
      |> crucible_v4_payload(trace, decision, trace_path)
      |> Map.merge(%{
        validation: validation_report(trace),
        trace: TraceAdapter.summarize_trace(trace),
        signals: TraceAdapter.summarize_signals(trace),
        capabilities: TraceAdapter.summarize_capabilities(trace),
        artifact_paths: Map.put(artifact_paths, :report_path, out)
      })

    report =
      OperatorReport.new!(
        schema: "trinity.crucible.replay.v1",
        mode: :replay,
        trace_id: trace.trace_id,
        validation: payload.validation,
        summaries: Map.take(payload, [:trace, :signals, :capabilities]),
        payload: payload,
        artifact_paths: payload.artifact_paths
      )
      |> OperatorReport.to_map()

    ArtifactIO.write_json!(out, normalize_for_json(report))
    kv("Wrote replay report", out)
    print_payload(report)
    pass("TRINITY CRUCIBLE REPLAY")
  end

  defp run_transcript_command(opts, command) do
    artifact_root = Keyword.get(opts, :artifact_root, "tmp/crucible_v5")
    name = Keyword.get(opts, :name, Enum.join(command, "_"))
    cwd = Keyword.get(opts, :cwd, File.cwd!())
    env = parse_env_assignments(Keyword.get_values(opts, :env))
    transcript_path = Path.join([artifact_root, "transcripts", "#{safe_artifact_name(name)}.log"])
    index_path = Path.join(artifact_root, "ARTIFACT_INDEX.md")

    File.mkdir_p!(Path.dirname(transcript_path))
    File.mkdir_p!(Path.dirname(index_path))

    {executable, args} = command_head!(command)
    started_at = DateTime.utc_now()
    header = transcript_header(command, cwd, env, started_at)

    {output, exit_code} =
      run_system_command!(executable, args, cwd, env, transcript_path, header)

    File.write!(transcript_path, header <> output <> transcript_footer(exit_code))
    append_transcript_index!(index_path, opts, command, cwd, env, exit_code, transcript_path)

    if exit_code == 0 do
      Mix.shell().info("transcript: #{transcript_path}")
      :ok
    else
      Mix.raise("transcript command failed with exit #{exit_code}: #{Enum.join(command, " ")}")
    end
  end

  defp hf_hub_artifact_download(args) do
    repo_id = Keyword.fetch!(args, :repo_id)
    filename = Keyword.fetch!(args, :filename)
    repo_type = Keyword.get(args, :repo_type, :dataset)
    revision = Keyword.fetch!(args, :revision)

    if Keyword.get(args, :offline_mode, false) do
      HfHub.try_to_load_from_cache(repo_id, filename, repo_type: repo_type, revision: revision)
    else
      HfHub.Download.hf_hub_download(
        repo_id: repo_id,
        filename: filename,
        repo_type: repo_type,
        revision: revision,
        token: Config.hf_hub_token(),
        progress_callback: Keyword.get(args, :progress_callback),
        verify_checksum: Keyword.get(args, :verify_checksum, false),
        expected_sha256: Keyword.get(args, :expected_sha256)
      )
    end
  end

  defp command_head!([executable | args]), do: {executable, args}

  defp run_system_command!(executable, args, cwd, env, transcript_path, header) do
    System.cmd(executable, args, cd: cwd, stderr_to_stdout: true, env: env)
  rescue
    error ->
      File.write!(transcript_path, header <> Exception.format(:error, error, __STACKTRACE__))
      reraise error, __STACKTRACE__
  end

  defp parse_env_assignments(assignments) do
    Enum.map(assignments, fn assignment ->
      case String.split(assignment, "=", parts: 2) do
        [key, value] -> {key, value}
        [key] -> {key, ""}
      end
    end)
  end

  defp transcript_header(command, cwd, env, started_at) do
    """
    # Crucible V5 Transcript
    command: #{Enum.join(command, " ")}
    cwd: #{cwd}
    env: #{format_env(env)}
    started_at: #{DateTime.to_iso8601(started_at)}

    """
  end

  defp transcript_footer(exit_code), do: "\nexit_code: #{exit_code}\n"

  defp append_transcript_index!(path, opts, command, cwd, env, exit_code, transcript_path) do
    ensure_transcript_index!(path)

    File.write!(
      path,
      transcript_index_row(%{
        phase: Keyword.get(opts, :phase, ""),
        command: Enum.join(command, " "),
        cwd: cwd,
        env: format_env(env),
        exit_code: exit_code,
        transcript: transcript_path,
        artifacts: "",
        git_commit: ""
      }),
      [:append]
    )
  end

  defp ensure_transcript_index!(path) do
    unless File.exists?(path) do
      File.write!(
        path,
        """
        # Crucible V5 Artifact Index

        | Phase | Command | CWD | Env | Exit | Transcript | Artifacts | Git commit |
        | --- | --- | --- | --- | --- | --- | --- | --- |
        """
      )
    end
  end

  defp transcript_index_row(entry) do
    [
      entry.phase,
      entry.command,
      entry.cwd,
      entry.env,
      entry.exit_code,
      entry.transcript,
      entry.artifacts,
      entry.git_commit
    ]
    |> Enum.map(&markdown_cell/1)
    |> then(&("| " <> Enum.join(&1, " | ") <> " |\n"))
  end

  defp format_env([]), do: ""

  defp format_env(env) do
    Enum.map_join(env, " ", fn {key, value} -> "#{key}=#{value}" end)
  end

  defp markdown_cell(value), do: value |> to_string() |> String.replace("|", "\\|")

  defp safe_artifact_name(name) do
    name
    |> to_string()
    |> String.trim()
    |> RefSanitizer.safe_fragment(allow_colon?: false, trim?: true)
    |> case do
      "" -> "command"
      safe -> safe
    end
  end

  defp route_demo(opts) do
    start_app!()

    context =
      opts
      |> route_context()
      |> validate_live_gate!()

    prepare_trace!(context, "TRINITY ROUTE DEMO")

    result =
      context.message
      |> initial_messages()
      |> run_single_node_loop(context)

    validate_trace!(context.trace_path, ["route_selected", "provider_called"])
    kv("Result", result.text)
    kv("Turns", result.turns)
    pass("TRINITY ROUTE DEMO")
  end

  defp eval(opts) do
    case Keyword.get(opts, :_args, []) do
      ["qwen_router_prompt_eval"] ->
        crucible_matrix_eval(opts)

      [] ->
        Mix.raise("usage: mix trinity.eval qwen_router_prompt_eval")

      [other | _rest] ->
        Mix.raise("unknown eval suite: #{other}")
    end
  end

  defp crucible_inspect(opts) do
    start_app!()

    cond do
      trace_path = Keyword.get(opts, :trace) ->
        crucible_inspect_trace(trace_path, opts)

      Keyword.get(opts, :live, false) ->
        crucible_inspect_live(opts)

      true ->
        crucible_inspect_mock(opts)
    end
  end

  defp crucible_inspect_mock(opts) do
    artifact_dir = Keyword.get(opts, :artifact_dir, default_artifact_dir())
    runtime_profile = runtime_profile(Keyword.get(opts, :runtime_profile), :mock_tiny)
    message = Keyword.get(opts, :message, @default_message)
    trace_path = Keyword.get(opts, :trace_out, "tmp/trinity_crucible/inspect.jsonl")

    banner("TRINITY CRUCIBLE INSPECT")

    {:ok, route} =
      Trinity.SingleNode.route(initial_messages(message),
        runtime_profile: runtime_profile,
        artifact_root: artifact_dir,
        trace_path: trace_path,
        trace_ref: "trinity-crucible-inspect",
        coordination_run_ref: "trinity-crucible-inspect"
      )

    trace_map = %{
      "schema" => "trinity.crucible.inspect.v1",
      "decision" => %{
        "role_id" => route.decision.selected_role_id,
        "agent_id" => route.decision.selected_agent_id,
        "confidence_band" => route.decision.confidence_band,
        "router_decision_ref" => route.decision.router_decision_ref
      },
      "tap_plan" => route.tap_plan,
      "crucible_trace" => TraceAdapter.to_map(route.crucible_trace),
      "trace_path" => trace_path
    }

    if out = Keyword.get(opts, :out) do
      ArtifactIO.write_json!(out, normalize_for_json(trace_map))
      kv("Wrote inspect report", out)
    end

    kv("Runtime profile", runtime_profile)
    kv("Trace id", route.crucible_trace.trace_id)
    kv("Tap plan", route.tap_plan.plan_id)
    kv("Selected role", role_name(route.decision.selected_role_id))
    kv("Selected agent", route.decision.selected_agent_id)
    kv("Trace path", trace_path)
    pass("TRINITY CRUCIBLE INSPECT")
  end

  defp crucible_inspect_trace(trace_path, opts) do
    banner("TRINITY CRUCIBLE TRACE INSPECT")

    trace = load_v4_trace!(trace_path)
    decision = CruciblePolicyPlan.evaluate(trace)

    artifact_paths =
      persist_crucible_decision_artifacts(
        :inspect_trace,
        trace,
        decision,
        Keyword.put(opts, :artifact_suffix, Path.basename(trace_path))
      )

    payload =
      :trace
      |> crucible_v4_payload(trace, decision, trace_path)
      |> Map.put(:artifact_paths, artifact_paths)

    out = Keyword.get(opts, :out) || v5_report_path("inspect_trace_#{trace.trace_id}.json", opts)
    ArtifactIO.write_json!(out, normalize_for_json(payload))
    kv("Wrote inspect report", out)

    print_payload(payload)
    pass("TRINITY CRUCIBLE TRACE INSPECT")
  end

  defp crucible_inspect_live(opts) do
    require_crucible_live!()

    banner("TRINITY CRUCIBLE LIVE INSPECT")

    prompt = Keyword.get(opts, :prompt) || Keyword.get(opts, :message) || "Hi"
    id = :"trinity-crucible-live-#{System.unique_integer([:positive])}"
    artifact_root = v5_artifact_root(opts)

    trace_name =
      Keyword.get(opts, :trace_name, "inspect_live_#{System.unique_integer([:positive])}")

    forward_timeout_ms = Keyword.get(opts, :forward_timeout_ms, 240_000)

    {:ok, pid} = CrucibleRuntime.start_child(crucible_live_runtime_opts(id, opts))
    {:ok, lease} = CrucibleRuntime.lease(pid, owner_ref: "trinity.crucible.inspect")

    try do
      tap_plan = live_tap_plan(:live_inspect, prompt, opts)

      {:ok, trace} =
        CrucibleRuntime.forward(pid, tap_plan, %{prompt: prompt},
          trace_name: trace_name,
          timeout: forward_timeout_ms
        )

      decision = CruciblePolicyPlan.evaluate(trace)
      trace_path = hosted_trace_path(trace_name, artifact_root)

      artifact_paths =
        persist_crucible_decision_artifacts(
          :inspect_live,
          trace,
          decision,
          with_trace_artifact_suffix(opts, trace_name)
        )

      payload =
        :live
        |> crucible_v4_payload(trace, decision, trace_path)
        |> Map.put(:artifact_paths, artifact_paths)

      out = Keyword.get(opts, :out) || v5_report_path("inspect_live_#{trace.trace_id}.json", opts)
      ArtifactIO.write_json!(out, normalize_for_json(payload))
      kv("Wrote live inspect report", out)

      print_payload(payload)
      pass("TRINITY CRUCIBLE LIVE INSPECT")
    after
      :ok = CrucibleRuntime.release(lease, timeout: max(forward_timeout_ms, 30_000))
      terminate_live_runtime(pid)
    end
  end

  defp crucible_matrix_eval(opts) do
    start_app!()

    cond do
      Keyword.get(opts, :live, false) ->
        crucible_matrix_eval_live(opts)

      Keyword.get_values(opts, :trace) != [] ->
        crucible_matrix_eval_traces(opts)

      true ->
        crucible_matrix_eval_mock(opts)
    end
  end

  defp crucible_matrix_eval_mock(opts) do
    artifact_dir = Keyword.get(opts, :artifact_dir, default_artifact_dir())
    runtime_profile = runtime_profile(Keyword.get(opts, :runtime_profile), :mock_tiny)
    selected_ids = Keyword.get_values(opts, :case)
    max_cases = Keyword.get(opts, :max_cases)
    cases = prompt_eval_cases(selected_ids, max_cases)
    out = Keyword.get(opts, :out, "tmp/trinity_crucible/matrix_eval.json")
    metadata = EvalMetadata.matrix(runtime_profile, artifact_dir)

    banner("TRINITY CRUCIBLE MATRIX EVAL")
    kv("Runtime profile", runtime_profile)
    kv("Eval mode", metadata.eval_mode)

    kv(
      "Qwen/Sakana artifact",
      if(metadata.qwen_artifact_ready?, do: "ready", else: "not ready")
    )

    kv("Acceptance level", metadata.acceptance_level)
    kv("Snapshot policy", metadata.snapshot_policy)
    kv("Cases", length(cases))

    {:ok, runtime} =
      Trinity.SingleNode.load_runtime(
        runtime_profile: runtime_profile,
        artifact_root: artifact_dir,
        messages: []
      )

    rows =
      Enum.map(cases, fn case_spec ->
        messages = case_messages(case_spec)

        {crucible_us, {:ok, crucible}} =
          timed(fn ->
            Trinity.SingleNode.route(messages,
              runtime: runtime,
              runtime_profile: runtime_profile,
              artifact_root: artifact_dir,
              trace_ref: "trace:matrix:#{Map.fetch!(case_spec, "id")}",
              coordination_run_ref: "matrix-eval"
            )
          end)

        trace = crucible.crucible_trace

        %{
          id: Map.fetch!(case_spec, "id"),
          crucible: crucible.decision,
          trace_id: trace.trace_id,
          trace_model_id: trace.model_id,
          trace_provider_kind: trace.provider_kind,
          trace_signal_count: length(trace.signals),
          final_logits_signal_id: trace.final_logits && trace.final_logits.signal_id,
          expected_role_id: expected_role_id(case_spec),
          expected_role_matched?:
            crucible.decision.selected_role_id == expected_role_id(case_spec),
          safety_expected?: expected_role_id(case_spec) == 2,
          trajectory_margin: trajectory_margin(trace),
          timings: %{
            crucible_us: crucible_us
          }
        }
      end)

    metadata = EvalMetadata.with_execution_observed(metadata, rows)
    report = crucible_matrix_report(rows, metadata)
    File.mkdir_p!(Path.dirname(out))
    ArtifactIO.write_json!(out, normalize_for_json(report))

    Mix.shell().info(format_crucible_matrix_report(report))
    kv("Wrote matrix report", out)

    if not Keyword.get(opts, :no_assert, false) and not report.accepted? do
      Mix.raise("trinity.crucible.matrix_eval failed strict acceptance criteria")
    end

    pass("TRINITY CRUCIBLE MATRIX EVAL")
  end

  defp crucible_matrix_eval_traces(opts) do
    trace_paths = expanded_trace_paths!(Keyword.get_values(opts, :trace))
    out = Keyword.get(opts, :out) || v5_report_path("matrix_eval_traces.json", opts)

    rows =
      Enum.map(trace_paths, fn path ->
        trace = load_v4_trace!(path)
        decision = CruciblePolicyPlan.evaluate(trace)

        artifact_paths =
          persist_crucible_decision_artifacts(
            :matrix_trace,
            trace,
            decision,
            Keyword.put(opts, :artifact_suffix, Path.basename(path))
          )

        %{
          mode: :trace,
          trace_path: path,
          trace_id: trace.trace_id,
          model_id: trace.model_id,
          provider_kind: trace.provider_kind,
          selected_policy: decision.selected_policy,
          selected_action: decision.selected_action,
          skipped_policies: decision.skipped_policies,
          artifact_paths: artifact_paths
        }
      end)

    File.mkdir_p!(Path.dirname(out))

    ArtifactIO.write_json!(
      out,
      normalize_for_json(%{schema: "trinity.crucible.matrix_eval.v4", rows: rows})
    )

    print_payload(%{ok: true, mode: :trace, rows: rows, out: out})
    pass("TRINITY CRUCIBLE MATRIX EVAL TRACE")
  end

  defp crucible_matrix_report(rows, metadata) do
    total = length(rows)
    expected_role_matches = Enum.count(rows, & &1.expected_role_matched?)
    strict_rows = Enum.count(rows, &strict_crucible_matrix_row?/1)

    metrics = %{
      total: total,
      expected_role_matches: expected_role_matches,
      expected_role_match_rate: ratio(expected_role_matches, total),
      contract_strictness: ratio(strict_rows, total),
      trajectory_margins: trajectory_margins(rows)
    }

    criteria = %{
      contract_strictness?: metrics.contract_strictness == 1.0
    }

    %{
      schema: "trinity.crucible.matrix_eval.v1",
      metadata: metadata,
      rows: rows,
      metrics: metrics,
      criteria: criteria,
      accepted?: Enum.all?(Map.values(criteria), &(&1 == true))
    }
  end

  defp format_crucible_matrix_report(report) do
    metrics = Map.fetch!(report, :metrics)
    criteria = Map.fetch!(report, :criteria)
    metadata = Map.fetch!(report, :metadata)

    """
    TRINITY Crucible Matrix Eval
      runtime profile: #{metadata.runtime_profile}
      eval mode: #{metadata.eval_mode}
      Qwen/Sakana artifact ready: #{metadata.qwen_artifact_ready?}
      runtime execution observed: #{metadata.runtime_execution_observed?}
      Qwen route execution observed: #{metadata.qwen_route_executed?}
      acceptance level: #{metadata.acceptance_level}
      snapshot policy: #{metadata.snapshot_policy}
      cases: #{metrics.total}
      expected role matches: #{metrics.expected_role_matches}
      expected role match rate: #{pct(metrics.expected_role_match_rate)}
      contract strictness: #{pct(metrics.contract_strictness)}

    Acceptance
      contract strictness == 100%: #{criteria.contract_strictness?}

    Result: #{if report.accepted?, do: "PASS", else: "FAIL"}
    """
  end

  defp strict_crucible_matrix_row?(row) do
    decision = Map.fetch!(row, :crucible)

    is_integer(decision.selected_role_id) and is_integer(decision.selected_agent_id) and
      decision.confidence_band in [:high, :medium, :low, :unknown] and
      is_binary(row.trace_id) and
      is_binary(row.trace_model_id) and
      is_atom(row.trace_provider_kind) and
      is_integer(row.trace_signal_count) and row.trace_signal_count > 0 and
      is_binary(row.final_logits_signal_id)
  end

  defp crucible_matrix_eval_live(opts) do
    require_crucible_live!()

    limit = Keyword.get(opts, :limit) || Keyword.get(opts, :max_cases) || 3
    cases = prompt_eval_cases([], limit)
    artifact_root = v5_artifact_root(opts)
    out = Keyword.get(opts, :out) || v5_report_path("matrix_eval_live_#{limit}.json", opts)
    id = :"trinity-crucible-matrix-live-#{System.unique_integer([:positive])}"

    run_tag =
      Keyword.get(opts, :run_tag, "matrix_eval_live_#{System.unique_integer([:positive])}")

    forward_timeout_ms = Keyword.get(opts, :forward_timeout_ms, 240_000)

    banner("TRINITY CRUCIBLE MATRIX EVAL LIVE")
    kv("Cases", length(cases))

    {:ok, pid} = CrucibleRuntime.start_child(crucible_live_runtime_opts(id, opts))
    {:ok, lease} = CrucibleRuntime.lease(pid, owner_ref: "trinity.crucible.matrix_eval")

    try do
      rows =
        cases
        |> Enum.with_index()
        |> Enum.map(fn {case_spec, index} ->
          trace_name = "#{run_tag}_#{index}"
          prompt = case_prompt(case_spec)
          tap_plan = live_tap_plan(:matrix_eval, prompt, opts, turn: index)

          {:ok, trace} =
            CrucibleRuntime.forward(pid, tap_plan, %{prompt: prompt},
              trace_name: trace_name,
              timeout: forward_timeout_ms
            )

          decision = CruciblePolicyPlan.evaluate(trace)

          artifact_paths =
            persist_crucible_decision_artifacts(
              :matrix_live,
              trace,
              decision,
              with_trace_artifact_suffix(opts, trace_name)
            )

          %{
            id: Map.fetch!(case_spec, "id"),
            trace_id: trace.trace_id,
            trace_path: hosted_trace_path(trace_name, artifact_root),
            model_id: trace.model_id,
            provider_kind: trace.provider_kind,
            selected_policy: decision.selected_policy,
            selected_action: decision.selected_action,
            hidden_state_available?: Enum.any?(trace.signals, &(&1.signal_type == :hidden_state)),
            skipped_policies: decision.skipped_policies,
            artifact_paths: artifact_paths
          }
        end)

      stability_report = maybe_run_role_boundary_stability(pid, opts, run_tag)

      report = %{
        schema: "trinity.crucible.matrix_eval_live.v5",
        ok: true,
        mode: :live,
        model_id: rows |> List.first(%{}) |> Map.get(:model_id),
        rows: rows,
        route_margin_histogram: Enum.frequencies_by(rows, & &1.selected_action),
        hidden_state_availability: %{
          available: Enum.count(rows, & &1.hidden_state_available?),
          unavailable: Enum.count(rows, &(not &1.hidden_state_available?))
        },
        role_boundary_stability: stability_report
      }

      File.mkdir_p!(Path.dirname(out))
      ArtifactIO.write_json!(out, normalize_for_json(report))
      print_payload(report)
      pass("TRINITY CRUCIBLE MATRIX EVAL LIVE")
    after
      :ok = CrucibleRuntime.release(lease, timeout: max(forward_timeout_ms, 30_000))
      terminate_live_runtime(pid)
    end
  end

  defp expanded_trace_paths!(trace_args) do
    paths =
      trace_args
      |> Enum.flat_map(&expand_trace_arg/1)
      |> Enum.uniq()
      |> Enum.sort()

    if paths == [] do
      Mix.raise("no trace files matched --trace arguments: #{inspect(trace_args)}")
    end

    paths
  end

  defp expand_trace_arg(path) when is_binary(path) do
    cond do
      File.dir?(path) ->
        path
        |> Path.join("**/*.jsonl")
        |> Path.wildcard()
        |> Enum.filter(&File.regular?/1)

      wildcard_path?(path) ->
        path
        |> Path.wildcard()
        |> Enum.filter(&File.regular?/1)

      File.regular?(path) ->
        [path]

      true ->
        []
    end
  end

  defp wildcard_path?(path), do: String.contains?(path, ["*", "?", "["])

  defp with_trace_artifact_suffix(opts, trace_name) do
    Keyword.put(opts, :artifact_suffix, "#{trace_name}.trace.jsonl")
  end

  defp persist_crucible_decision_artifacts(mode, trace, decision, opts) do
    root = v5_artifact_root(opts)

    name =
      [
        mode,
        trace.trace_id || System.unique_integer([:positive]),
        Keyword.get(opts, :artifact_suffix)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("_")

    policy_path =
      Path.join([
        root,
        "policy_decisions",
        "#{safe_artifact_name(name)}.policy_decision.json"
      ])

    route_path =
      Path.join([
        root,
        "route_decisions",
        "#{safe_artifact_name(name)}.route_decision.json"
      ])

    ArtifactIO.write_json!(
      policy_path,
      normalize_for_json(policy_decision_payload(trace, decision))
    )

    ArtifactIO.write_json!(
      route_path,
      normalize_for_json(route_decision_payload(trace, decision))
    )

    %{policy_decision_path: policy_path, route_decision_path: route_path}
  end

  defp policy_decision_payload(trace, decision) do
    %{
      schema: "trinity.crucible.policy_decision.v5",
      trace_id: trace.trace_id,
      model_id: trace.model_id,
      provider_kind: trace.provider_kind,
      selected_policy: decision.selected_policy,
      selected_action: decision.selected_action,
      confidence: decision.confidence,
      evidence: decision.evidence,
      skipped_policies: decision.skipped_policies,
      fallback_path: decision.fallback_path,
      errors: decision.errors
    }
  end

  defp route_decision_payload(trace, decision) do
    %{
      schema: "trinity.crucible.route_decision.v5",
      router_decision_ref: decision.decision_id,
      trace_ref: trace.trace_id,
      provider_kind: trace.provider_kind,
      model_id: trace.model_id,
      model_family: trace.model_family,
      backend: trace.backend,
      assigned_role: decision.selected_action,
      decision_source: decision.selected_policy,
      confidence: decision.confidence,
      target_model: nil,
      fallback_path: decision.fallback_path,
      evidence_count: length(decision.evidence),
      skipped_policies: decision.skipped_policies
    }
  end

  defp maybe_run_role_boundary_stability(pid, opts, run_tag) do
    repeats = Keyword.get(opts, :stability_repeats, 0)

    if is_integer(repeats) and repeats > 0 do
      run_role_boundary_stability(pid, opts, run_tag, repeats)
    end
  end

  defp run_role_boundary_stability(pid, opts, run_tag, repeats) do
    prompt = Keyword.get(opts, :stability_prompt, Keyword.get(opts, :prompt, "Hi"))
    artifact_root = v5_artifact_root(opts)
    timeout = Keyword.get(opts, :forward_timeout_ms, 240_000)

    rows =
      Enum.map(1..repeats, fn index ->
        trace_name = "#{run_tag}_stability_#{index}"
        tap_plan = live_tap_plan(:live_inspect, prompt, opts, turn: index)

        {:ok, trace} =
          CrucibleRuntime.forward(pid, tap_plan, %{prompt: prompt},
            trace_name: trace_name,
            timeout: timeout
          )

        decision = CruciblePolicyPlan.evaluate(trace)

        artifact_paths =
          persist_crucible_decision_artifacts(
            :role_stability_live,
            trace,
            decision,
            with_trace_artifact_suffix(opts, trace_name)
          )

        %{
          index: index,
          trace_id: trace.trace_id,
          trace_path: hosted_trace_path(trace_name, artifact_root),
          selected_policy: decision.selected_policy,
          selected_action: decision.selected_action,
          artifact_paths: artifact_paths,
          evidence_summary: policy_evidence_summary(decision)
        }
      end)

    report = %{
      schema: "trinity.crucible.role_boundary_stability.v5",
      prompt_digest: CrucibleSignalTrace.Digest.prefixed_text(prompt),
      repeat_count: repeats,
      selected_action_counts: Enum.frequencies_by(rows, & &1.selected_action),
      selected_policy_counts: Enum.frequencies_by(rows, & &1.selected_policy),
      entropy_variance: evidence_variance(rows, :entropy),
      margin_variance: evidence_variance(rows, :margin),
      rows: rows
    }

    path = v5_report_path("role_boundary_stability_#{run_tag}.json", opts)
    ArtifactIO.write_json!(path, normalize_for_json(report))
    Map.put(report, :report_path, path)
  end

  defp policy_evidence_summary(decision) do
    %{
      evidence_count: length(decision.evidence),
      entropy: policy_evidence_value(decision.evidence, :entropy_limit),
      margin: policy_evidence_value(decision.evidence, :margin_floor)
    }
  end

  defp policy_evidence_value(evidence, rule) do
    evidence
    |> Enum.find_value(fn item ->
      if Map.get(item, :rule) == rule, do: Map.get(item, :value)
    end)
    |> numeric_or_nil()
  end

  defp numeric_or_nil(value) when is_number(value), do: value
  defp numeric_or_nil(_value), do: nil

  defp evidence_variance(rows, key) do
    rows
    |> Enum.map(&get_in(&1, [:evidence_summary, key]))
    |> Enum.reject(&is_nil/1)
    |> sample_variance()
  end

  defp sample_variance([]), do: nil
  defp sample_variance([_value]), do: 0.0

  defp sample_variance(values) do
    mean = Enum.sum(values) / length(values)

    values
    |> Enum.map(fn value -> :math.pow(value - mean, 2) end)
    |> Enum.sum()
    |> Kernel./(length(values) - 1)
  end

  defp crucible_live_runtime_opts(id, opts) do
    [
      id: id,
      live_model?: true,
      provider_module: SelfHostedInferenceBumblebee.CrucibleProvider,
      model_id: Keyword.get(opts, :model_id),
      tokenizer_id: Keyword.get(opts, :tokenizer_id),
      backend: Keyword.get(opts, :backend),
      architecture: normalize_live_architecture(Keyword.get(opts, :architecture)),
      artifact_root: v5_artifact_root(opts)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp live_tap_plan(surface, prompt, opts, extra \\ []) do
    runtime_profile = runtime_profile(Keyword.get(opts, :runtime_profile), :live)

    context =
      RequestContext.from_messages(initial_messages(prompt),
        task_type: live_task_type(surface),
        turn: Keyword.get(extra, :turn, 0),
        runtime_profile: %{name: runtime_profile},
        artifact_root: Keyword.get(opts, :artifact_root),
        trace_out: Keyword.get(opts, :trace_out),
        policy_id: "trinity:crucible:#{surface}"
      )

    case surface do
      :matrix_eval -> TapPlanBuilder.matrix_eval_plan(context, %{name: runtime_profile})
      :live_inspect -> TapPlanBuilder.live_inspect_plan(context, %{name: runtime_profile})
    end
  end

  defp live_task_type(:matrix_eval), do: :review
  defp live_task_type(:live_inspect), do: :verification

  defp normalize_live_architecture(nil), do: nil
  defp normalize_live_architecture("base"), do: :base

  defp normalize_live_architecture("for_causal_language_modeling"),
    do: :for_causal_language_modeling

  defp normalize_live_architecture("for-causal-language-modeling"),
    do: :for_causal_language_modeling

  defp normalize_live_architecture("for_sequence_classification"),
    do: :for_sequence_classification

  defp normalize_live_architecture("for-sequence-classification"),
    do: :for_sequence_classification

  defp normalize_live_architecture(other) do
    Mix.raise("unsupported --architecture #{inspect(other)}")
  end

  defp hosted_trace_path(trace_name, artifact_root) do
    CrucibleArtifacts.trace_path("hosted_#{trace_name}", root: artifact_root)
  end

  defp terminate_live_runtime(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(SelfHostedInferenceCore.CrucibleRuntimeSupervisor, pid)
    :ok
  catch
    :exit, _reason -> :ok
  end

  defp v5_report_path(filename, opts) do
    Path.join([v5_artifact_root(opts), "reports", filename])
  end

  defp v5_artifact_root(opts) do
    root = Keyword.get(opts, :artifact_root) || "tmp/crucible_v5"

    CrucibleArtifacts.ensure_layout!(root: root)
  end

  defp crucible_v4_payload(mode, trace, decision, trace_path) do
    %{
      ok: true,
      mode: mode,
      provider_kind: trace.provider_kind,
      model_id: trace.model_id,
      trace_path: trace_path,
      route_decision: %{
        assigned_role: decision.selected_action,
        decision_source: decision.selected_policy,
        confidence: decision.confidence,
        target_model: nil
      },
      policy_used: decision.selected_policy,
      skipped_policies:
        Enum.map(decision.skipped_policies, fn skipped ->
          {skipped.policy, skipped.reason}
        end),
      unsupported_capabilities: unsupported_capabilities(trace),
      evidence: decision.evidence
    }
  end

  defp unsupported_capabilities(%{capability_report: %{unsupported: unsupported}})
       when is_list(unsupported),
       do: unsupported

  defp unsupported_capabilities(_trace), do: []

  @spec load_v4_trace!(String.t()) :: Crucible.ForwardTrace.t()
  defp load_v4_trace!(path), do: CrucibleTraceIngest.from_jsonl!(path, [])

  defp validation_report(trace) do
    %{
      shape: validation_status(CrucibleTraceValidate.validate_forward_trace(trace, :shape)),
      replay: validation_status(CrucibleTraceValidate.validate_forward_trace(trace, :replay))
    }
  end

  defp validation_status(:ok), do: "ok"
  defp validation_status({:error, reason}), do: inspect(reason)

  defp case_prompt(case_spec) do
    case_spec
    |> Map.get("messages", [])
    |> case do
      [%{"content" => content} | _rest] -> content
      [content | _rest] when is_binary(content) -> content
      _other -> @default_message
    end
  end

  defp hitl_mock_loop(opts) do
    start_app!()

    context =
      opts
      |> route_context()
      |> Map.merge(%{
        allow_live?: false,
        mock?: true,
        provider_pool: "mock",
        trace_path: Keyword.get(opts, :trace_out, @default_mock_trace_path),
        run_id: Keyword.get(opts, :run_id, "hitl_mock")
      })

    prepare_trace!(context, "TRINITY HITL MOCK ORCHESTRATOR LOOP")

    result =
      context.message
      |> initial_messages()
      |> run_single_node_loop(context)

    validate_trace!(context.trace_path, ["slm_extracted", "route_selected", "provider_called"])
    kv("Mock turns executed", result.turns)
    kv("Loop result", result.text)
    pass("TRINITY HITL MOCK ORCHESTRATOR LOOP")
  end

  defp hitl_gpu do
    start_app!()
    banner("TRINITY HITL GPU CHECK")

    platforms = Preflight.require_cuda!()
    kv("CUDA platform", Map.get(platforms, :cuda))
    Preflight.put_cuda_backend!()

    tensor =
      Nx.iota({8, 8}, type: :f32)
      |> Nx.dot(Nx.iota({8, 8}, type: :f32))

    ensure_shape!(tensor, {8, 8}, "CUDA smoke tensor")
    ensure_cuda_tensor!(tensor, "CUDA smoke tensor")
    pass("TRINITY HITL GPU CHECK")
  end

  defp hitl_vector do
    start_app!()
    path = default_router_vector_path()

    banner("TRINITY HITL ROUTER VECTOR CHECK")
    kv("Source vector path", path)
    ensure_regular_file!(path, "router vector")
    kv("Source vector sha256", ArtifactIO.file_sha256!(path))

    vector = SVD.load_router_vector!(path, default_router_vector_tensor())
    split = SVD.split_router_vector(vector, 9_216, 1_024, 10)

    ensure_shape!(vector, {19_456}, "router vector")
    ensure_shape!(split.scale_offsets, {9_216}, "scale offsets")
    ensure_shape!(split.head_weights, {10, 1_024}, "router head weights")
    kv("scale_count", split.scale_count)
    kv("head_count", split.head_count)
    pass("TRINITY HITL ROUTER VECTOR CHECK")
  end

  defp hitl_base_qwen do
    start_app!()
    banner("TRINITY HITL BASE QWEN CHECK")
    Profile.put_default_backend!(:cuda_exla)

    {:ok, {model_info, tokenizer}} = SLMProfile.load_profile(:qwen_coordinator)
    kv("Profile", :qwen_coordinator)
    kv("Model hidden size", model_info.spec.hidden_size)

    messages = [
      %{"role" => "user", "content" => "Hello TRINITY. Prove the router can see me."}
    ]

    {:ok, meta} =
      Extractor.extract_and_route(model_info, tokenizer, messages, fn vector ->
        ensure_shape!(vector, {1, 1_024}, "Qwen penultimate vector")
        ensure_cuda_tensor!(vector, "Qwen penultimate vector")
        {:ok, %{agent_id: 0, role_id: 0}}
      end)

    kv("Tokenizer input shapes", meta.input_shapes)
    kv("Hidden state shape", meta.hidden_state_shape)
    kv("Vector shape", meta.vector_shape)
    pass("TRINITY HITL BASE QWEN CHECK")
  end

  defp hitl_head_route do
    start_app!()
    banner("TRINITY HITL HEAD ROUTE CHECK")
    Profile.put_default_backend!(:cuda_exla)

    vector = SVD.load_router_vector!(default_router_vector_path(), default_router_vector_tensor())
    split = SVD.split_router_vector(vector, 9_216, 1_024, 10)

    {:ok, head_state} =
      HeadLoader.build_routing_state(split.head_weights, backend: {EXLA.Backend, client: :cuda})

    {:ok, {model_info, tokenizer}} = SLMProfile.load_profile(:qwen_coordinator)

    messages = [
      %{"role" => "user", "content" => "Route this request through the Sakana head."}
    ]

    {:ok, routed} =
      Extractor.extract_and_route(model_info, tokenizer, messages, fn hidden_vector ->
        route =
          RoutingHead.route(
            head_state.model,
            head_state.params,
            hidden_vector,
            head_state.num_agents,
            head_state.num_roles
          )

        ensure_shape!(hidden_vector, {1, 1_024}, "Qwen penultimate vector")
        ensure_cuda_tensor!(hidden_vector, "Qwen penultimate vector")
        ensure_shape!(route.logits, {1, 10}, "routing logits")
        ensure_cuda_tensor!(route.logits, "routing logits")
        {:ok, route}
      end)

    route = routed.route
    kv("Agent id", route.agent_id)
    kv("Role id", route.role_id)
    kv("Role name", role_name(route.role_id))
    kv("Agent logits", short_logits(route.agent_logits))
    kv("Role logits", short_logits(route.role_logits))
    pass("TRINITY HITL HEAD ROUTE CHECK")
  end

  defp hitl_adapted(opts) do
    start_app!()

    artifact_dir = Keyword.get(opts, :artifact_dir, default_artifact_dir())
    runtime_profile = runtime_profile(Keyword.get(opts, :runtime_profile), :cuda_exla)

    compare_path =
      Keyword.get(opts, :compare_path, "decoder.blocks.26.self_attention.query.kernel")

    message = Keyword.get(opts, :message, @default_message)

    banner("TRINITY HITL ADAPTED COORDINATOR CHECK")
    Profile.put_default_backend!(runtime_profile)

    {:ok, {base_info, _base_tokenizer}} = SLMProfile.load_profile(:qwen_coordinator)

    {:ok, coordinator} =
      QwenSakanaLoader.load(artifact_dir: artifact_dir, runtime_profile: runtime_profile)

    manifest = coordinator.manifest
    kv("Artifact dir", coordinator.artifact_dir)
    kv("Artifact status", manifest["status"])
    kv("Artifact layout", manifest["artifact_layout"])
    kv("Artifact export complete", manifest["export_complete"])
    kv("Selected tensor count", manifest["selected_tensor_count"])
    kv("Selected singular value count", manifest["selected_singular_value_count"])
    kv("Hidden size", coordinator.hidden_size)
    kv("Num agents", coordinator.num_agents)
    kv("Num roles", coordinator.num_roles)

    ensure_manifest_contract!(manifest)
    prove_tensor_patch!(base_info.params, coordinator.model_info.params, compare_path)

    messages = [%{"role" => "user", "content" => message}]
    {:ok, logits} = QwenSakanaLoader.route(coordinator, messages)

    kv("Agent id", logits.selected_agent_id)
    kv("Role id", logits.selected_role_id)
    kv("Role name", role_name(logits.selected_role_id))
    kv("Agent logits", Enum.take(logits.agent_logits, 5))
    kv("Role logits", logits.role_logits)
    pass("TRINITY HITL ADAPTED COORDINATOR CHECK")
  end

  defp sakana_export_adapted(opts) do
    start_app!()

    out_dir = Path.expand(Keyword.get(opts, :out, default_artifact_dir()))
    source_vector = Keyword.get(opts, :source_vector, default_router_vector_path())
    tensor_name = Keyword.get(opts, :tensor_name, "trinity_router_es_vector")
    dry_run? = Keyword.get(opts, :dry_run, false)
    force? = Keyword.get(opts, :force, false)
    resume? = Keyword.get(opts, :resume, false)
    only_index = Keyword.get(opts, :only_index)
    skip_existing? = Keyword.get(opts, :skip_existing, true)
    svd_compute_type = svd_compute_type(Keyword.get(opts, :svd_compute_type, "source"))
    runtime_profile = runtime_profile(Keyword.get(opts, :runtime_profile), :cuda_exla)

    banner("TRINITY SAKANA ADAPTED EXPORT")
    kv("Output directory", out_dir)
    kv("Source vector", source_vector)
    kv("Source tensor", tensor_name)
    kv("Dry run", dry_run?)
    kv("SVD compute type", svd_compute_type)
    kv("Runtime profile", runtime_profile)
    validate_output_policy!(out_dir, force?, resume?, dry_run?)
    ensure_regular_file!(source_vector, "source vector")

    vector = SVD.load_router_vector!(source_vector, tensor_name)
    split = SVD.split_router_vector(vector, 9_216, 1_024, 10)

    manifest =
      export_manifest_seed(
        selected_manifest_entries(),
        vector,
        split,
        source_vector,
        tensor_name,
        svd_compute_type
      )

    if dry_run? do
      print_export_manifest(manifest, split)
    else
      manifest =
        run_sakana_export!(
          out_dir,
          vector,
          split,
          source_vector,
          tensor_name,
          svd_compute_type,
          runtime_profile,
          only_index: only_index,
          force: force?,
          skip_existing: skip_existing?
        )

      kv("Export status", manifest["status"])
      kv("Export complete", manifest["export_complete"])
      kv("Completed tensors", completed_selected_tensors(manifest))
    end

    pass("TRINITY SAKANA ADAPTED EXPORT")
  end

  defp sakana_import_python(opts) do
    start_app!()

    source_dir = Keyword.get(opts, :source_dir)
    manifest_path = Keyword.get(opts, :manifest) || default_python_manifest_path(source_dir)
    reference_path = Keyword.get(opts, :reference)
    out_dir = Keyword.get(opts, :out, default_artifact_dir())
    force? = Keyword.get(opts, :force, false)
    resume? = Keyword.get(opts, :resume, false)
    json? = Keyword.get(opts, :json, false)

    banner("TRINITY SAKANA IMPORT PYTHON")
    kv("Python manifest", manifest_path)
    kv("Reference manifest", reference_path || "(none)")
    kv("Output directory", out_dir)
    validate_output_policy!(out_dir, force?, resume?, false)
    ensure_regular_file!(manifest_path, "Python manifest")

    python_manifest = ArtifactIO.load_json!(manifest_path)
    reference = load_optional_json(reference_path)
    selected = PythonImporter.normalize_selected_entries(python_manifest, reference)

    imported =
      python_manifest
      |> Map.take(["schema", "created_at", "source", "source_vector_sha256"])
      |> Map.put("artifact_version", 1)
      |> Map.put("status", "imported_python_semantic")
      |> Map.put("export_complete", false)
      |> Map.put("selected_tensor_count", length(selected))
      |> Map.put(
        "selected_singular_value_count",
        Enum.reduce(selected, 0, &(&2 + Map.get(&1, "singular_values", 0)))
      )
      |> Map.put("selected_tensors", selected)
      |> Map.put(
        "source_manifest_path",
        PythonImporter.provenance_path(manifest_path, File.cwd!())
      )
      |> maybe_put("source_dir", source_dir)

    File.mkdir_p!(out_dir)
    ArtifactIO.write_json!(Path.join(out_dir, "python_import_manifest.json"), imported)

    if json? do
      imported |> normalize_for_json() |> Jason.encode!(pretty: true) |> Mix.shell().info()
    end

    kv("Imported selected tensors", length(selected))
    kv("Wrote import manifest", Path.join(out_dir, "python_import_manifest.json"))
    pass("TRINITY SAKANA IMPORT PYTHON")
  end

  defp sakana_large_tensor_chunks(opts) do
    start_app!()

    python_report_path = Keyword.get(opts, :python_report, default_reference_manifest_path())

    out = Keyword.get(opts, :out, @default_large_tensor_out)
    chunk_rows = Keyword.get(opts, :chunk_rows, LargeTensorChunks.default_chunk_rows())
    sources = Keyword.get_values(opts, :source)
    report = ArtifactIO.load_json!(python_report_path)
    selected = selected_tensors_from_report(report)

    component_metadata = %{
      "selected_tensors" =>
        selected
        |> Enum.map(&normalize_large_tensor_entry/1)
        |> Enum.filter(&(Map.get(&1, "source_name") in chunk_sources(sources)))
    }

    chunk_checks =
      component_metadata
      |> LargeTensorChunks.baseline_plan(chunk_rows: chunk_rows, sources: chunk_sources(sources))
      |> Enum.flat_map(&chunk_entries/1)

    output = %{
      "schema" => "trinity_sakana_large_tensor_chunks.v1",
      "inputs" => %{
        "python_report" => python_report_path,
        "components_dir" => Keyword.get(opts, :components_dir),
        "stage_dir" => Keyword.get(opts, :stage_dir),
        "chunk_rows" => chunk_rows,
        "require_cuda" => not Keyword.get(opts, :no_cuda, false)
      },
      "large_tensor_chunk_checks" => chunk_checks,
      "summary" => large_tensor_summary(chunk_checks, chunk_sources(sources))
    }

    ArtifactIO.write_json!(out, output)
    summary = output["summary"]
    kv("Wrote large-tensor chunk report", out)
    kv("large_tensor_chunks", summary["chunk_count"])
    kv("required_checks", summary["required_check_count"])
    kv("failed_required", summary["failed_required_count"])
    pass("TRINITY SAKANA LARGE TENSOR CHUNKS")
  end

  defp sakana_parity_sample(opts) do
    start_app!()

    out = Keyword.get(opts, :out, @default_parity_sample_out)
    python_report = load_optional_json(Keyword.get(opts, :python_report))

    reference =
      load_optional_json(Keyword.get(opts, :reference, default_reference_manifest_path()))

    router_vector = Keyword.get(opts, :router_vector, default_router_vector_path())

    native? =
      not (Keyword.get(opts, :semantic_only, false) or Keyword.get(opts, :skip_native_svd, false))

    report = %{
      "schema" => "trinity_sakana_parity_sample.v1",
      "inputs" => %{
        "router_vector" => router_vector,
        "reference" => Keyword.get(opts, :reference, default_reference_manifest_path()),
        "components_dir" => Keyword.get(opts, :components_dir),
        "stage_dir" => Keyword.get(opts, :stage_dir),
        "require_cuda" => not Keyword.get(opts, :no_cuda, false),
        "native" => native?,
        "semantic_only" => Keyword.get(opts, :semantic_only, false)
      },
      "reference" => reference_summary(reference),
      "python_current_baseline" => current_python_baseline_report(python_report),
      "native_elixir_svd_variants" => native_router_vector_variant(router_vector, native?),
      "semantic_python_component_variants" => semantic_variants(python_report, opts)
    }

    ArtifactIO.write_json!(out, report)
    kv("Wrote Elixir parity report", out)
    print_hash_summary(report)
    pass("TRINITY SAKANA PARITY SAMPLE")
  end

  defp sakana_router_trace(opts) do
    start_app!()

    artifact_dir = Keyword.get(opts, :artifact_dir, default_artifact_dir())
    runtime_profile = runtime_profile(Keyword.get(opts, :runtime_profile), :cuda_exla)
    message = Keyword.get(opts, :message, @default_message)
    out = Keyword.get(opts, :out)
    python_report = load_optional_json(Keyword.get(opts, :python_report))
    messages = [%{"role" => "user", "content" => message}]

    banner("TRINITY SAKANA ROUTER TRACE")

    {:ok, route} =
      Trinity.SingleNode.route(messages,
        artifact_root: artifact_dir,
        runtime_profile: runtime_profile
      )

    report =
      %{
        "schema" => @default_router_trace_schema,
        "artifact_dir" => artifact_dir,
        "runtime_profile" => Atom.to_string(runtime_profile),
        "message" => message,
        "transcript_sha256" => route.logits.transcript_hash,
        "token_count" => route.logits.token_count,
        "agent_id" => route.logits.selected_agent_id,
        "role_id" => route.logits.selected_role_id,
        "agent_logits" => route.logits.agent_logits,
        "role_logits" => route.logits.role_logits,
        "backend_label" => inspect(route.logits.backend_label),
        "route_hash_inputs" => route.logits.route_hash_inputs
      }
      |> maybe_put("comparison", maybe_compare_router_trace(python_report, route.logits))

    if out do
      ArtifactIO.write_json!(out, report)
      kv("Wrote router trace", out)
    end

    case report["comparison"] do
      %{"failed_required" => failed} when failed > 0 ->
        Mix.raise("router trace comparison failed_required=#{failed}")

      _ ->
        :ok
    end

    kv("Agent id", route.logits.selected_agent_id)
    kv("Role id", route.logits.selected_role_id)
    pass("TRINITY SAKANA ROUTER TRACE")
  end

  defp parity_check(opts) do
    python_report = require_regular_path!(opts, :python_report)
    elixir_report = require_regular_path!(opts, :elixir_report)
    summary_out = Keyword.get(opts, :summary_out)
    started_ms = System.monotonic_time(:millisecond)

    python = ArtifactIO.load_json!(python_report)
    elixir = ArtifactIO.load_json!(elixir_report)
    comparison = compare_parity_reports(python, elixir, opts)
    duration_ms = System.monotonic_time(:millisecond) - started_ms

    output = parity_output(comparison)
    Mix.shell().info(output)

    if summary_out do
      ArtifactIO.write_json!(
        summary_out,
        comparison
        |> Map.put("schema_version", @summary_schema_version)
        |> Map.put("duration_ms", duration_ms)
        |> Map.put("python_report", python_report)
        |> Map.put("elixir_report", elixir_report)
        |> Map.put("stdout_tail", tail_bytes(output, @tail_bytes))
        |> Map.put("stderr_tail", nil)
      )
    end

    if comparison["ok"] do
      :ok
    else
      Mix.raise("parity comparator failed; see output above")
    end
  end

  defp compare_parity_reports(python, elixir, opts) do
    expected = reference_hash(python) || reference_hash(elixir)
    python_hashes = collect_hashes(python)
    elixir_hashes = collect_hashes(elixir)
    baseline = current_python_baseline(python, python_hashes)
    stage_checks = collect_stage_checks(elixir)
    large_checks = collect_large_tensor_chunk_checks(elixir)

    context = %{
      expected: expected,
      python_hashes: python_hashes,
      elixir_hashes: elixir_hashes,
      baseline: baseline,
      stage_checks: stage_checks,
      large_checks: large_checks
    }

    failures = parity_failures(context, opts)

    %{
      "ok" => failures == [],
      "failures" => failures,
      "stored_reference_expected" => expected,
      "python_reference_hash_reproducible" =>
        boolish(get_in(python, ["reference", "expected_hash_reproducible"])),
      "current_python_baseline" => %{"label" => elem(baseline, 0), "sha256" => elem(baseline, 1)},
      "python_hashes" => python_hashes,
      "elixir_hashes" => elixir_hashes,
      "cross_report_identical_hashes" => cross_report_hashes(python_hashes, elixir_hashes),
      "stage_summary" => checks_summary(stage_checks),
      "large_tensor_chunk_summary" => checks_summary(large_checks),
      "wrapper_options" => wrapper_options_snapshot(opts)
    }
  end

  defp parity_failures(context, opts) do
    []
    |> maybe_failure(
      strict_reference_failed?(context, opts),
      "strict stored-reference comparison failed"
    )
    |> maybe_failure(
      strict_current_python_failed?(context, opts),
      "strict current-Python comparison failed"
    )
    |> maybe_failure(
      missing_strict_stage_checks?(context, opts),
      "strict stage-tolerance comparison failed: no stage checks found"
    )
    |> maybe_failure(
      strict_stage_failed?(context, opts),
      "strict stage-tolerance comparison failed"
    )
    |> maybe_failure(
      strict_large_stage_failed?(context, opts),
      "strict large-tensor chunk stage-tolerance comparison failed"
    )
    |> Enum.reverse()
  end

  defp strict_reference_failed?(context, opts) do
    Keyword.get(opts, :strict_reference, false) and
      not reference_match?(context.expected, context.python_hashes, context.elixir_hashes)
  end

  defp strict_current_python_failed?(context, opts) do
    Keyword.get(opts, :strict_current_python, false) and
      not current_python_match?(context.baseline, context.elixir_hashes)
  end

  defp missing_strict_stage_checks?(context, opts) do
    Keyword.get(opts, :strict_stage_tolerances, true) and context.stage_checks == [] and
      context.large_checks == []
  end

  defp strict_stage_failed?(context, opts) do
    Keyword.get(opts, :strict_stage_tolerances, true) and context.stage_checks != [] and
      not all_required_checks_passed?(context.stage_checks)
  end

  defp strict_large_stage_failed?(context, opts) do
    Keyword.get(opts, :strict_stage_tolerances, true) and context.large_checks != [] and
      not all_required_checks_passed?(context.large_checks)
  end

  defp route_context(opts) do
    mock? = Keyword.get(opts, :mock_provider, Keyword.get(opts, :mock, false))

    %{
      allow_live?: Keyword.get(opts, :allow_live, false),
      artifact_dir: Keyword.get(opts, :artifact_dir, default_artifact_dir()),
      runtime_profile: runtime_profile(Keyword.get(opts, :runtime_profile), :cuda_exla),
      max_turns: Keyword.get(opts, :max_turns, 5),
      message: Keyword.get(opts, :message, @default_message),
      mock?: mock?,
      openai_api_key: Keyword.get(opts, :openai_api_key),
      provider_pool: Keyword.get(opts, :provider_pool, if(mock?, do: "mock", else: "default")),
      run_id: Keyword.get(opts, :run_id, "route_demo"),
      trace_content: parse_trace_content(Keyword.get(opts, :trace_content, "hash")),
      trace_path: Keyword.get(opts, :trace_out, @default_route_trace_path)
    }
  end

  defp validate_live_gate!(%{mock?: true} = context), do: context

  defp validate_live_gate!(%{allow_live?: true} = context), do: context

  defp validate_live_gate!(_context) do
    Mix.raise(
      "live provider demo is gated; pass --mock-provider for local smoke or --allow-live for live providers"
    )
  end

  defp prepare_trace!(context, label) do
    File.mkdir_p!(Path.dirname(context.trace_path))
    File.rm(context.trace_path)
    banner(label)
    kv("Artifact dir", context.artifact_dir)
    kv("Runtime profile", context.runtime_profile)
    kv("Provider pool", context.provider_pool)
    kv("Provider mode", if(context.mock?, do: :mock, else: :live))
    kv("Trace path", context.trace_path)
    context
  end

  defp run_single_node_loop(messages, context) do
    turns = max(context.max_turns || 1, 1)

    Enum.reduce_while(1..turns, %{messages: messages, receipt: nil}, fn turn, acc ->
      emit_extraction_trace!(context, turn, acc.messages)

      route_opts = [
        artifact_root: context.artifact_dir,
        runtime_profile: context.runtime_profile,
        trace_path: context.trace_path,
        trace_ref: context.run_id,
        coordination_run_ref: context.run_id,
        turn: turn
      ]

      dispatch_opts = [
        provider_pool: context.provider_pool,
        allow_live: context.allow_live?,
        openai_api_key: context.openai_api_key,
        trace_path: context.trace_path,
        trace_ref: context.run_id,
        coordination_run_ref: context.run_id,
        turn: turn,
        mock_response: mock_response(turn)
      ]

      with {:ok, route} <- Trinity.SingleNode.route(acc.messages, route_opts),
           {:ok, receipt} <- Trinity.SingleNode.dispatch(route, acc.messages, dispatch_opts) do
        text = receipt_text(receipt)
        next_messages = acc.messages ++ [%{"role" => "assistant", "content" => text}]
        {:cont, %{messages: next_messages, receipt: receipt}}
      else
        {:error, reason} -> Mix.raise("single-node route demo failed: #{inspect(reason)}")
      end
    end)
    |> then(fn %{messages: messages, receipt: receipt} ->
      %{turns: turns, text: receipt_text(receipt), messages: messages}
    end)
  end

  defp emit_extraction_trace!(context, turn, messages) do
    event = %TraceEvent{
      event_ref: generated_ref("trace-event:slm"),
      event_type: :slm_extracted,
      trace_ref: context.run_id,
      coordination_run_ref: context.run_id,
      payload: %{
        turn: turn,
        token_count: token_count(messages),
        runtime_profile: context.runtime_profile
      }
    }

    JsonlSink.emit(event, path: context.trace_path, content: context.trace_content)
  end

  defp validate_trace!(trace_path, required_events) do
    unless File.exists?(trace_path), do: raise("trace file was not written: #{trace_path}")

    events =
      trace_path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)
      |> Enum.map(&Map.get(&1, "event"))

    missing = Enum.reject(required_events, &(&1 in events))

    unless missing == [] do
      raise "trace file missing required events #{inspect(missing)}; observed=#{inspect(events)}"
    end
  end

  defp ensure_manifest_contract!(manifest) do
    assert!(manifest["status"] == "complete", {:invalid_artifact_status, manifest["status"]})
    assert!(manifest["export_complete"] == true, :artifact_export_incomplete)

    assert!(
      manifest["selected_tensor_count"] == 9,
      {:invalid_selected_tensor_count, manifest["selected_tensor_count"]}
    )

    assert!(
      manifest["selected_singular_value_count"] == 9_216,
      {:invalid_selected_singular_value_count, manifest["selected_singular_value_count"]}
    )
  end

  defp prove_tensor_patch!(base_params, adapted_params, path) do
    base_entries = SVD.flatten_tensor_entries(base_params) |> Map.new(&{&1.path, &1.tensor})
    adapted_entries = SVD.flatten_tensor_entries(adapted_params) |> Map.new(&{&1.path, &1.tensor})

    base = Map.fetch!(base_entries, path)
    adapted = Map.fetch!(adapted_entries, path)

    max_diff =
      adapted
      |> Nx.as_type(:f32)
      |> Nx.subtract(Nx.as_type(base, :f32))
      |> Nx.abs()
      |> Nx.reduce_max()
      |> Nx.to_number()

    kv("Adapted tensor compare path", path)
    kv("Base tensor backend", Preflight.tensor_backend(base))
    kv("Adapted tensor backend", Preflight.tensor_backend(adapted))
    kv("Adapted tensor max_abs_diff", max_diff)
    assert!(max_diff > 0.0, {:adapted_tensor_equals_base, path})
  end

  defp validate_output_policy!(_out_dir, _force?, _resume?, true), do: :ok

  defp validate_output_policy!(out_dir, force?, resume?, false) do
    out_dir
    |> File.stat()
    |> validate_output_stat!(out_dir, force? or resume?)
  end

  defp validate_output_stat!({:ok, %File.Stat{type: :directory}}, _out_dir, true), do: :ok

  defp validate_output_stat!({:ok, %File.Stat{type: :directory}}, out_dir, false) do
    Mix.raise("Output directory exists: #{out_dir}. Use --force or --resume to proceed.")
  end

  defp validate_output_stat!({:ok, %File.Stat{type: _}}, out_dir, _allowed?) do
    Mix.raise("Output path exists but is not a directory: #{out_dir}")
  end

  defp validate_output_stat!({:error, :enoent}, _out_dir, _allowed?), do: :ok

  defp selected_manifest_entries do
    [
      selected_manifest_entry("embedder.token_embedding.kernel", [151_936, 1_024], 1_024),
      selected_manifest_entry(
        "decoder.blocks.26.self_attention.query.kernel",
        [1_024, 2_048],
        1_024
      ),
      selected_manifest_entry(
        "decoder.blocks.26.self_attention.key.kernel",
        [1_024, 1_024],
        1_024
      ),
      selected_manifest_entry(
        "decoder.blocks.26.self_attention.value.kernel",
        [1_024, 1_024],
        1_024
      ),
      selected_manifest_entry(
        "decoder.blocks.26.self_attention.output.kernel",
        [2_048, 1_024],
        1_024
      ),
      selected_manifest_entry("decoder.blocks.26.ffn.gate.kernel", [1_024, 3_072], 1_024),
      selected_manifest_entry("decoder.blocks.26.ffn.intermediate.kernel", [1_024, 3_072], 1_024),
      selected_manifest_entry("decoder.blocks.26.ffn.output.kernel", [3_072, 1_024], 1_024),
      selected_manifest_entry("language_modeling_head.output.kernel", [1_024, 151_936], 1_024)
    ]
  end

  defp selected_manifest_entry(path, shape, singular_values) do
    %{
      "path" => path,
      "segments" => [],
      "shape" => shape,
      "singular_values" => singular_values
    }
  end

  defp export_manifest_seed(selected, vector, split, source_vector, tensor_name, svd_compute_type) do
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    selected_tensors = selected_export_entries(selected, svd_compute_type)

    %{
      "artifact_version" => 1,
      "status" => "pending",
      "created_at" => now,
      "updated_at" => now,
      "base_model_repo" => "Qwen/Qwen3-0.6B",
      "architecture" => "for_causal_language_modeling",
      "xla_target" => "cuda12",
      "export_backend" => "elixir_nx_exla_cuda",
      "source_vector_path" => source_vector,
      "source_vector_tensor" => tensor_name,
      "source_vector_shape" => vector |> Nx.shape() |> Tuple.to_list(),
      "source_vector_sha256" => ArtifactIO.file_sha256!(source_vector),
      "scale_offset_count" => split.scale_count,
      "router_head_shape" => split.head_weights |> Nx.shape() |> Tuple.to_list(),
      "router_head_artifact" => ArtifactIO.router_head_file(),
      "router_head_tensor_key" => ArtifactIO.router_head_tensor_key(),
      "adapted_tensors_artifact" => ArtifactIO.adapted_tensors_file(),
      "artifact_layout" => "checkpoint_directory",
      "selected_tensor_count" => length(selected_tensors),
      "selected_singular_value_count" =>
        Enum.reduce(selected_tensors, 0, &(&2 + &1["singular_values"])),
      "export_complete" => false,
      "selected_tensors" => selected_tensors,
      "source_split" => %{
        "scale_count" => split.scale_count,
        "hidden_size" => 1_024,
        "output_count" => 10
      },
      "split" => %{"scale_count" => split.scale_count, "head_count" => split.head_count}
    }
  end

  defp selected_export_entries(selected, svd_compute_type) do
    selected
    |> Enum.with_index(1)
    |> Enum.map_reduce(0, fn {entry, index}, cursor ->
      singular_values = selected_entry_singular_values(entry)
      path = selected_entry_path(entry)
      shape = selected_entry_shape(entry)
      type = selected_entry_type(entry)

      item = %{
        "index" => index,
        "path" => path,
        "artifact_key" => path,
        "segments" => selected_entry_segments(entry),
        "shape" => shape,
        "type" => type,
        "source_type" => type,
        "svd_compute_type" => Atom.to_string(svd_compute_type),
        "status" => "pending",
        "offset_start" => cursor,
        "offset_end" => cursor + singular_values,
        "singular_values" => singular_values,
        "checkpoint_path" =>
          Path.join(ArtifactIO.checkpoint_directory_name(), checkpoint_file(index, path)),
        "backend_observed_during_export" => nil,
        "decompose_elapsed_ms" => nil,
        "reconstruct_elapsed_ms" => nil,
        "u_backend" => nil,
        "s_backend" => nil,
        "v_backend" => nil,
        "adapted_backend" => nil,
        "error" => nil,
        "checkpoint_sha256" => nil
      }

      {item, cursor + singular_values}
    end)
    |> elem(0)
  end

  defp selected_entry_path(%{path: path}) when is_binary(path), do: path
  defp selected_entry_path(%{"path" => path}) when is_binary(path), do: path

  defp selected_entry_segments(%{segments: segments}) when is_list(segments), do: segments
  defp selected_entry_segments(%{"segments" => segments}) when is_list(segments), do: segments
  defp selected_entry_segments(_entry), do: []

  defp selected_entry_shape(%{tensor: %Nx.Tensor{} = tensor}) do
    tensor |> Nx.shape() |> Tuple.to_list()
  end

  defp selected_entry_shape(%{"shape" => shape}) when is_list(shape), do: shape

  defp selected_entry_singular_values(%{"singular_values" => singular_values})
       when is_integer(singular_values) do
    singular_values
  end

  defp selected_entry_singular_values(%{tensor: %Nx.Tensor{} = tensor}) do
    tensor |> Nx.shape() |> Tuple.to_list() |> Enum.min()
  end

  defp selected_entry_type(%{tensor: %Nx.Tensor{} = tensor}), do: inspect(Nx.type(tensor))
  defp selected_entry_type(%{"type" => type}) when is_binary(type), do: type
  defp selected_entry_type(_entry), do: "{:f, 32}"

  defp checkpoint_file(index, path) do
    index = index |> Integer.to_string() |> String.pad_leading(4, "0")
    safe_path = path |> String.to_charlist() |> Enum.map(&checkpoint_path_char/1) |> to_string()
    "#{index}_#{safe_path}.safetensors"
  end

  defp checkpoint_path_char(char)
       when char in ?A..?Z or char in ?a..?z or char in ?0..?9 or char in [?_, ?., ?-] do
    char
  end

  defp checkpoint_path_char(_char), do: ?_

  defp print_export_manifest(manifest, split) do
    Mix.shell().info("Dry run complete: no files written")
    kv("Source vector shape", manifest["source_vector_shape"])
    kv("Scale offsets shape", Nx.shape(split.scale_offsets))
    kv("Router head shape", Nx.shape(split.head_weights))
    kv("Selected tensor count", manifest["selected_tensor_count"])
    kv("Selected singular values", manifest["selected_singular_value_count"])
  end

  defp run_sakana_export!(
         out_dir,
         vector,
         split,
         source_vector,
         tensor_name,
         svd_compute_type,
         runtime_profile,
         opts
       ) do
    force? = Keyword.fetch!(opts, :force)
    only_index = Keyword.fetch!(opts, :only_index)
    skip_existing? = Keyword.fetch!(opts, :skip_existing)

    prepare_sakana_export_output!(out_dir, force?)
    Profile.put_default_backend!(runtime_profile)

    {:ok, {model_info, _tokenizer}} =
      SLMProfile.load_profile(:qwen_coordinator)
      |> normalize_model_load_result!()

    selected = qwen_layer26_selected_tensors!(model_info)
    validate_sakana_selection!(selected, split.scale_offsets)

    manifest =
      export_manifest_seed(
        selected,
        vector,
        split,
        source_vector,
        tensor_name,
        svd_compute_type
      )
      |> Map.put("only_index", only_index)
      |> Map.put("skip_existing", skip_existing?)

    ArtifactIO.write_manifest!(out_dir, manifest)

    manifest =
      out_dir
      |> write_router_head!(split.head_weights, manifest, skip_existing?)
      |> export_selected_tensor_checkpoints!(
        out_dir,
        selected,
        split.scale_offsets,
        selected_tensors_to_process(manifest, only_index),
        svd_compute_type,
        runtime_profile,
        skip_existing?
      )
      |> finalize_sakana_export!(out_dir, only_index)

    kv("Wrote manifest", ArtifactIO.manifest_path(out_dir))
    kv("Wrote router head", Path.join(out_dir, ArtifactIO.router_head_file()))
    manifest
  end

  defp normalize_model_load_result!({:ok, value}), do: {:ok, value}

  defp normalize_model_load_result!({:error, reason}) do
    Mix.raise("failed to load qwen_coordinator profile for export: #{inspect(reason)}")
  end

  defp prepare_sakana_export_output!(out_dir, true) do
    File.rm_rf!(out_dir)
    prepare_sakana_export_output!(out_dir, false)
  end

  defp prepare_sakana_export_output!(out_dir, false) do
    File.mkdir_p!(ArtifactIO.checkpoint_path(out_dir))
  end

  defp qwen_layer26_selected_tensors!(model_info) do
    model_info.params
    |> SVD.decomposable_tensor_entries(path_filter: SVD.layer_index_filter([26]))
    |> tap(fn selected ->
      if selected == [] do
        Mix.raise("no Qwen layer-26 decomposable tensors selected for Sakana export")
      end
    end)
  end

  defp validate_sakana_selection!(selected, scale_offsets) do
    singular_count = SVD.singular_value_count(selected)
    scale_count = Nx.size(scale_offsets)

    unless singular_count == scale_count do
      Mix.raise(
        "selected tensor singular count mismatch: expected #{scale_count}, got #{singular_count}"
      )
    end
  end

  defp write_router_head!(out_dir, head_weights, manifest, skip_existing?) do
    head_path = Path.join(out_dir, ArtifactIO.router_head_file())
    head_key = manifest["router_head_tensor_key"] || ArtifactIO.router_head_tensor_key()

    if skip_existing? and File.regular?(head_path) do
      Map.put(manifest, "router_head_sha256", ArtifactIO.file_sha256!(head_path))
    else
      ArtifactIO.write_tensors!(head_path, %{head_key => head_weights})
      Map.put(manifest, "router_head_sha256", ArtifactIO.file_sha256!(head_path))
    end
    |> then(fn updated ->
      ArtifactIO.write_manifest!(out_dir, updated)
      updated
    end)
  end

  defp export_selected_tensor_checkpoints!(
         manifest,
         out_dir,
         selected,
         scale_offsets,
         to_process,
         svd_compute_type,
         runtime_profile,
         skip_existing?
       ) do
    source_tensors = Map.new(selected, &{&1.path, &1.tensor})

    Enum.reduce(to_process, manifest, fn entry, current ->
      source_tensor = Map.fetch!(source_tensors, entry["path"])

      if skip_existing? and checkpoint_valid?(out_dir, entry) do
        current
      else
        export_selected_tensor_checkpoint!(
          current,
          out_dir,
          source_tensor,
          entry,
          scale_offsets,
          svd_compute_type,
          runtime_profile
        )
      end
    end)
  end

  defp export_selected_tensor_checkpoint!(
         manifest,
         out_dir,
         source_tensor,
         entry,
         scale_offsets,
         svd_compute_type,
         runtime_profile
       ) do
    running =
      manifest
      |> update_selected_tensor(entry["index"], %{"status" => "running", "error" => nil})
      |> Map.put("updated_at", now_iso8601())

    ArtifactIO.write_manifest!(out_dir, running)

    offset_start = entry["offset_start"]
    singular_count = entry["singular_values"]
    offsets = Nx.slice(scale_offsets, [offset_start], [singular_count])

    {decompose_ms, decomposition, decompose_source} =
      timed_sakana_decompose!(source_tensor, svd_compute_type)

    ensure_export_backend!(decomposition.u, entry["path"], runtime_profile)
    ensure_export_backend!(decomposition.s, entry["path"], runtime_profile)
    ensure_export_backend!(decomposition.v, entry["path"], runtime_profile)
    ensure_export_backend!(source_tensor, entry["path"], runtime_profile)

    {reconstruct_ms, adapted_tensor, reconstructed_before_cast} =
      timed_sakana_reconstruct!(decomposition, offsets, source_tensor)

    ensure_export_backend!(adapted_tensor, entry["path"], runtime_profile)

    checkpoint_sha =
      write_sakana_checkpoint!(
        out_dir,
        entry["checkpoint_path"],
        entry["artifact_key"],
        adapted_tensor
      )

    updated =
      running
      |> update_selected_tensor(entry["index"], %{
        "status" => "complete",
        "decompose_elapsed_ms" => decompose_ms,
        "reconstruct_elapsed_ms" => reconstruct_ms,
        "checkpoint_sha256" => checkpoint_sha,
        "svd_compute_type" => Atom.to_string(svd_compute_type),
        "decompose_source_type" => inspect(Nx.type(decompose_source)),
        "reconstructed_type_before_cast" => inspect(Nx.type(reconstructed_before_cast)),
        "checkpoint_type" => inspect(Nx.type(adapted_tensor)),
        "u_backend" => Preflight.tensor_backend(decomposition.u),
        "s_backend" => Preflight.tensor_backend(decomposition.s),
        "v_backend" => Preflight.tensor_backend(decomposition.v),
        "adapted_backend" => Preflight.tensor_backend(adapted_tensor),
        "error" => nil
      })
      |> Map.put("updated_at", now_iso8601())

    ArtifactIO.write_manifest!(out_dir, updated)
    updated
  rescue
    exception ->
      failed =
        manifest
        |> update_selected_tensor(entry["index"], %{
          "status" => "failed",
          "error" => Exception.message(exception)
        })
        |> Map.put("status", "failed")
        |> Map.put("updated_at", now_iso8601())

      ArtifactIO.write_manifest!(out_dir, failed)
      reraise exception, __STACKTRACE__
  end

  defp timed_sakana_decompose!(source_tensor, svd_compute_type) do
    started = System.monotonic_time(:millisecond)
    decompose_source = decompose_source_tensor(source_tensor, svd_compute_type)
    decomposition = SVD.decompose_tensor(decompose_source)

    Exporter.sync_tensor!(decomposition.u)
    Exporter.sync_tensor!(decomposition.s)
    Exporter.sync_tensor!(decomposition.v)

    elapsed_ms = System.monotonic_time(:millisecond) - started
    {elapsed_ms, decomposition, decompose_source}
  end

  defp decompose_source_tensor(tensor, :source), do: tensor
  defp decompose_source_tensor(tensor, :f32), do: Nx.as_type(tensor, :f32)

  defp timed_sakana_reconstruct!(decomposition, offsets, source_tensor) do
    started = System.monotonic_time(:millisecond)

    reconstructed =
      SVD.reconstruct(decomposition, Nx.as_type(offsets, Nx.type(decomposition.s)))

    adapted =
      reconstructed
      |> Nx.as_type(Nx.type(source_tensor))
      |> Exporter.sync_tensor!()

    elapsed_ms = System.monotonic_time(:millisecond) - started
    {elapsed_ms, adapted, reconstructed}
  end

  defp ensure_export_backend!(tensor, path, runtime_profile) do
    profile = Profile.resolve(runtime_profile)
    backend = Preflight.tensor_backend(tensor)

    unless Profile.accepts_backend_label?(profile, backend) do
      Mix.raise("unaccepted export backend for #{path}: #{backend} profile=#{profile.name}")
    end
  end

  defp write_sakana_checkpoint!(out_dir, relative_path, artifact_key, tensor) do
    path = Path.join(out_dir, relative_path)
    ArtifactIO.write_tensors!(path, %{artifact_key => tensor})
    ArtifactIO.file_sha256!(path)
  end

  defp checkpoint_valid?(out_dir, entry) do
    path = Path.join(out_dir, entry["checkpoint_path"])

    with true <- File.regular?(path),
         expected when is_binary(expected) <- entry["checkpoint_sha256"],
         true <- expected == ArtifactIO.file_sha256!(path),
         %Nx.Tensor{} = tensor <- ArtifactIO.read_tensor!(path, entry["artifact_key"]) do
      Nx.shape(tensor) == List.to_tuple(entry["shape"]) and
        inspect(Nx.type(tensor)) == entry["type"]
    else
      _ -> false
    end
  end

  defp selected_tensors_to_process(manifest, nil), do: manifest["selected_tensors"]

  defp selected_tensors_to_process(manifest, only_index) do
    selected = Enum.filter(manifest["selected_tensors"], &(&1["index"] == only_index))

    if selected == [] do
      Mix.raise("invalid --only-index value #{only_index}")
    end

    selected
  end

  defp finalize_sakana_export!(manifest, out_dir, nil) do
    status =
      if all_selected_tensors_complete?(manifest) do
        %{"status" => "complete", "export_complete" => true}
      else
        %{"status" => "partial", "export_complete" => false}
      end

    finalized =
      manifest
      |> Map.merge(status)
      |> Map.put("updated_at", now_iso8601())

    ArtifactIO.write_manifest!(out_dir, finalized)
    finalized
  end

  defp finalize_sakana_export!(manifest, out_dir, _only_index) do
    partial =
      manifest
      |> Map.put("status", "partial")
      |> Map.put("export_complete", false)
      |> Map.put("updated_at", now_iso8601())

    ArtifactIO.write_manifest!(out_dir, partial)
    partial
  end

  defp all_selected_tensors_complete?(manifest) do
    manifest["selected_tensors"] != [] and
      Enum.all?(manifest["selected_tensors"], &(&1["status"] == "complete"))
  end

  defp completed_selected_tensors(manifest) do
    Enum.count(manifest["selected_tensors"], &(&1["status"] == "complete"))
  end

  defp update_selected_tensor(manifest, index, updates) do
    selected =
      Enum.map(manifest["selected_tensors"], fn entry ->
        if entry["index"] == index, do: Map.merge(entry, updates), else: entry
      end)

    Map.put(manifest, "selected_tensors", selected)
  end

  defp selected_tensors_from_report(report) do
    cond do
      is_list(report["selected_tensors"]) ->
        report["selected_tensors"]

      is_list(report["semantic_python_component_variants"]) ->
        Enum.map(report["semantic_python_component_variants"], fn variant ->
          %{
            "source_name" => variant["source_name"],
            "shape" => variant["shape"] || variant["source_shape"] || [0]
          }
        end)

      true ->
        []
    end
  end

  defp normalize_large_tensor_entry(entry) do
    source = entry["source_name"] || entry["python_name"] || entry["source"] || entry["path"]
    shape = entry["shape"] || entry["source_shape"] || [0]

    %{
      "source_name" => source,
      "safe_key" => LargeTensorChunks.sanitize_python_key(source),
      "shape" => shape
    }
  end

  defp chunk_sources([]), do: LargeTensorChunks.default_sources()
  defp chunk_sources(sources), do: sources

  defp chunk_entries(%{
         "source_name" => source,
         "safe_key" => safe_key,
         "shape" => shape,
         "chunks" => chunks
       }) do
    Enum.map(chunks, fn chunk ->
      %{
        "label" => "#{safe_key}.chunk_#{chunk["chunk_index"]}",
        "source_name" => source,
        "safe_key" => safe_key,
        "shape" => shape,
        "chunk_index" => chunk["chunk_index"],
        "row_start" => chunk["row_start"],
        "row_end" => chunk["row_end"],
        "checks" => [
          %{
            "stage" => "semantic_chunk_plan",
            "shape_match" => true,
            "byte_match" => nil,
            "functional_passed" => true,
            "required_for_functional_parity" => false,
            "tolerance" => nil
          }
        ],
        "stage_debug" => %{
          "functional_parity_passed" => true,
          "required_failed_count" => 0
        }
      }
    end)
  end

  defp large_tensor_summary(chunks, sources) do
    checks = Enum.flat_map(chunks, & &1["checks"])
    required = Enum.filter(checks, &boolish(&1["required_for_functional_parity"]))
    failed = Enum.reject(required, &boolish(&1["functional_passed"]))

    %{
      "sources" => sources,
      "chunk_count" => length(chunks),
      "stage_check_count" => length(checks),
      "required_check_count" => length(required),
      "failed_required_count" => length(failed),
      "functional_parity_passed" => failed == []
    }
  end

  defp native_router_vector_variant(_path, false), do: []

  defp native_router_vector_variant(path, true) do
    if File.regular?(path) do
      vector = SVD.load_router_vector!(path, default_router_vector_tensor())

      split =
        SVD.split_router_vector(
          vector,
          ParityTrace.scale_count(),
          ParityTrace.hidden_size(),
          ParityTrace.output_count()
        )

      [
        %{
          "label" => "framework_router_vector_split",
          "observed_bf16_sha256" => nil,
          "matches_expected" => nil,
          "matches_python_current" => nil,
          "zero_offset_max_abs_error_vs_source" => 0.0,
          "source_vector_shape" => vector |> Nx.shape() |> Tuple.to_list(),
          "router_head_shape" => split.head_weights |> Nx.shape() |> Tuple.to_list()
        }
      ]
    else
      []
    end
  end

  defp semantic_variants(nil, _opts), do: nil

  defp semantic_variants(report, opts) when is_map(report) do
    variants = report["semantic_python_component_variants"]

    cond do
      is_list(variants) ->
        variants

      is_list(report["selected_tensors"]) ->
        selected =
          report
          |> PythonImporter.normalize_selected_entries(nil)
          |> maybe_filter_selected(Keyword.get(opts, :selected_source_filter))

        Enum.map(selected, fn entry ->
          %{
            "label" => "semantic_import.#{entry["safe_key"]}",
            "source_name" => entry["source_name"],
            "elixir_name" => entry["path"],
            "shape" => entry["shape"],
            "observed_bf16_sha256" => nil,
            "matches_expected" => nil,
            "matches_python_current" => nil,
            "zero_offset_max_abs_error_vs_source" => nil,
            "stage_debug" => %{"checks" => []}
          }
        end)

      true ->
        []
    end
  end

  defp maybe_filter_selected(entries, nil), do: entries

  defp maybe_filter_selected(entries, filter) do
    Enum.filter(entries, fn entry ->
      String.contains?(entry["source_name"] || entry["path"] || "", filter)
    end)
  end

  defp print_hash_summary(report) do
    kv("Stored Python bf16 hash", get_in(report, ["reference", "expected_bf16_sha256"]))
    current = get_in(report, ["python_current_baseline", "observed_bf16_sha256"])
    kv("Current Python baseline hash", current || "(no --python-report supplied)")
    kv("Native Elixir SVD variants", length(report["native_elixir_svd_variants"] || []))

    case report["semantic_python_component_variants"] do
      variants when is_list(variants) -> kv("Semantic variants", length(variants))
      nil -> kv("Semantic variants", "(no Python semantic component report supplied)")
      other -> kv("Semantic variants", other)
    end
  end

  defp maybe_compare_router_trace(nil, _logits), do: nil

  defp maybe_compare_router_trace(python, logits) do
    checks = [
      exact_check("schema", python["schema"], @default_router_trace_schema),
      exact_check("transcript_sha256", python["transcript_sha256"], logits.transcript_hash),
      exact_check("agent_id", python["agent_id"], logits.selected_agent_id),
      exact_check("role_id", python["role_id"], logits.selected_role_id)
    ]

    failed = Enum.reject(checks, & &1["passed"])

    %{
      "checks" => checks,
      "failed_required" => length(failed)
    }
  end

  defp exact_check(name, expected, actual) do
    %{
      "name" => name,
      "expected" => expected,
      "actual" => actual,
      "passed" => expected == actual
    }
  end

  defp parity_output(comparison) do
    [
      "stored reference expected: #{comparison["stored_reference_expected"]}",
      "python reference hash reproducible: #{comparison["python_reference_hash_reproducible"]}",
      "current Python baseline: #{get_in(comparison, ["current_python_baseline", "label"])} #{get_in(comparison, ["current_python_baseline", "sha256"])}",
      "",
      "Python variants:",
      hash_lines(comparison["python_hashes"]),
      "",
      "Elixir variants:",
      hash_lines(comparison["elixir_hashes"]),
      "",
      "Cross-report identical hashes:",
      cross_hash_lines(comparison["cross_report_identical_hashes"]),
      "",
      "Stage checks: #{inspect(comparison["stage_summary"])}",
      "Large tensor chunk checks: #{inspect(comparison["large_tensor_chunk_summary"])}",
      if(comparison["ok"],
        do: "PASS parity.check",
        else: "FAIL parity.check #{inspect(comparison["failures"])}"
      )
    ]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp hash_lines(hashes) when map_size(hashes) == 0, do: ["  (none)"]

  defp hash_lines(hashes) do
    Enum.map(hashes, fn {label, digest} -> "  #{label}: #{digest}" end)
  end

  defp cross_hash_lines([]), do: ["  (none)"]

  defp cross_hash_lines(matches) do
    Enum.map(matches, fn match ->
      "  #{match["python_label"]} == #{match["elixir_label"]}: #{match["sha256"]}"
    end)
  end

  defp collect_hashes(report) do
    ["variants", "native_elixir_svd_variants", "semantic_python_component_variants"]
    |> Enum.flat_map(fn key -> report[key] || [] end)
    |> Enum.filter(&is_map/1)
    |> Enum.reduce(%{}, fn item, acc ->
      label = item["label"]
      digest = item["observed_bf16_sha256"]

      if is_binary(label) and is_binary(digest) do
        Map.put(acc, label, digest)
      else
        acc
      end
    end)
  end

  defp collect_stage_checks(report) do
    report
    |> Map.get("semantic_python_component_variants", [])
    |> Enum.flat_map(fn
      %{"stage_debug" => %{"checks" => checks}} = variant when is_list(checks) ->
        Enum.map(checks, &Map.merge(&1, variant_context(variant)))

      _ ->
        []
    end)
  end

  defp collect_large_tensor_chunk_checks(report) do
    report
    |> Map.get("large_tensor_chunk_checks", [])
    |> Enum.flat_map(fn
      %{"stage_debug" => %{"checks" => checks}} = chunk when is_list(checks) ->
        Enum.map(checks, &Map.merge(&1, chunk_context(chunk)))

      %{"checks" => checks} = chunk when is_list(checks) ->
        Enum.map(checks, &Map.merge(&1, chunk_context(chunk)))

      _ ->
        []
    end)
  end

  defp variant_context(variant) do
    %{
      "variant_label" => variant["label"],
      "source_name" => variant["source_name"],
      "elixir_name" => variant["elixir_name"]
    }
  end

  defp chunk_context(chunk) do
    %{
      "variant_label" => chunk["label"],
      "source_name" => chunk["source_name"],
      "elixir_name" => chunk["elixir_name"],
      "chunk_index" => chunk["chunk_index"],
      "row_start" => chunk["row_start"],
      "row_end" => chunk["row_end"]
    }
  end

  defp checks_summary(checks) do
    required = Enum.filter(checks, &boolish(&1["required_for_functional_parity"]))
    failed = Enum.reject(required, &boolish(&1["functional_passed"]))

    %{
      "total_checks" => length(checks),
      "required_checks" => length(required),
      "failed_required" => length(failed),
      "functional_parity_passed" => failed == []
    }
  end

  defp all_required_checks_passed?(checks) do
    checks
    |> Enum.filter(&boolish(&1["required_for_functional_parity"]))
    |> Enum.all?(&boolish(&1["functional_passed"]))
  end

  defp reference_hash(report), do: get_in(report, ["reference", "expected_bf16_sha256"])

  defp current_python_baseline(report, hashes) do
    label = get_in(report, ["reference", "current_python_baseline_label"])
    digest = get_in(report, ["reference", "current_python_baseline_bf16_sha256"])

    cond do
      is_binary(label) and is_binary(digest) ->
        {label, digest}

      map_size(hashes) > 0 ->
        Enum.at(hashes, 0)

      true ->
        {nil, nil}
    end
  end

  defp current_python_baseline_report(nil), do: nil

  defp current_python_baseline_report(report) do
    hashes = collect_hashes(report)
    {label, digest} = current_python_baseline(report, hashes)

    %{
      "label" => label,
      "observed_bf16_sha256" => digest,
      "expected_hash_reproducible" =>
        boolish(get_in(report, ["reference", "expected_hash_reproducible"]))
    }
  end

  defp reference_summary(nil), do: %{}

  defp reference_summary(reference) do
    %{
      "expected_bf16_sha256" =>
        get_in(reference, ["reference", "expected_bf16_sha256"]) ||
          reference["expected_bf16_sha256"],
      "selected_tensor_count" => ParityTrace.reference_selected_tensor_count(reference),
      "selected_singular_value_count" =>
        ParityTrace.reference_selected_singular_value_count(reference)
    }
  end

  defp reference_match?(nil, _python_hashes, _elixir_hashes), do: false

  defp reference_match?(expected, python_hashes, elixir_hashes) do
    Enum.any?(Map.values(python_hashes), &(&1 == expected)) and
      Enum.any?(Map.values(elixir_hashes), &(&1 == expected))
  end

  defp current_python_match?({_label, nil}, _elixir_hashes), do: false

  defp current_python_match?({_label, digest}, elixir_hashes) do
    Enum.any?(Map.values(elixir_hashes), &(&1 == digest))
  end

  defp cross_report_hashes(python_hashes, elixir_hashes) do
    for {python_label, python_digest} <- python_hashes,
        {elixir_label, ^python_digest} <- elixir_hashes do
      %{
        "python_label" => python_label,
        "elixir_label" => elixir_label,
        "sha256" => python_digest
      }
    end
  end

  defp wrapper_options_snapshot(opts) do
    Enum.into(opts, %{}, fn {key, value} -> {Atom.to_string(key), value} end)
  end

  defp maybe_failure(failures, true, message), do: [message | failures]
  defp maybe_failure(failures, false, _message), do: failures

  defp require_regular_path!(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, path} when is_binary(path) and path != "" ->
        ensure_regular_file!(path, Atom.to_string(key))
        path

      _ ->
        Mix.raise("--#{String.replace(Atom.to_string(key), "_", "-")} is required")
    end
  end

  defp ensure_regular_file!(path, label) do
    unless File.regular?(path) do
      Mix.raise("#{label} is not a regular file: #{path}")
    end
  end

  defp ensure_shape!(%Nx.Tensor{} = tensor, shape, label),
    do: ensure_shape!(Nx.shape(tensor), shape, label)

  defp ensure_shape!(shape, shape, _label), do: :ok

  defp ensure_shape!(actual, expected, label) do
    raise "#{label} shape mismatch: expected #{inspect(expected)}, got #{inspect(actual)}"
  end

  defp ensure_cuda_tensor!(%Nx.Tensor{} = tensor, label) do
    backend = Preflight.tensor_backend(tensor)
    assert!(String.contains?(backend, "cuda"), {label, :not_cuda, backend})
  end

  defp assert!(true, _reason), do: :ok
  defp assert!(false, reason), do: raise("TRINITY assertion failed: #{inspect(reason)}")

  defp runtime_profile(nil, default), do: default

  defp runtime_profile(profile, _default), do: Config.normalize_runtime_profile!(profile)

  defp svd_compute_type("source"), do: :source
  defp svd_compute_type("f32"), do: :f32
  defp svd_compute_type(:source), do: :source
  defp svd_compute_type(:f32), do: :f32

  defp svd_compute_type(other) do
    Mix.raise("invalid --svd-compute-type #{inspect(other)}; expected source or f32")
  end

  defp default_pin_path, do: Path.join(framework_root(), "priv/sakana_trinity/artifact_pin.json")

  defp default_artifact_dir do
    Path.join(framework_root(), "priv/sakana_trinity/adapted_qwen3_0_6b_layer26")
  end

  defp default_router_vector_path do
    Path.join(
      framework_root(),
      "priv/sakana_trinity/artifacts/trinity_router_es_vector.safetensors"
    )
  end

  defp default_router_vector_tensor, do: @default_router_vector_tensor

  defp default_reference_manifest_path do
    Path.join(
      framework_root(),
      "priv/sakana_trinity/reference/sakana_python_reference_manifest.json"
    )
  end

  defp now_iso8601 do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end

  defp default_python_manifest_path(nil), do: "trinity_sakana_export_manifest.json"

  defp default_python_manifest_path(source_dir) do
    Path.join(source_dir, PythonImporter.default_manifest())
  end

  defp framework_root do
    source_root = Path.expand("../../../../..", __DIR__)

    [File.cwd!(), source_root]
    |> Enum.find(fn dir ->
      File.regular?(Path.join(dir, "build_support/workspace_contract.exs"))
    end) ||
      source_root
  end

  defp load_optional_json(nil), do: nil

  defp load_optional_json(path) do
    if File.regular?(path), do: ArtifactIO.load_json!(path), else: nil
  end

  defp prompt_eval_cases(selected_ids, max_cases) do
    path =
      Path.join([
        framework_root(),
        "examples",
        "qwen_router_prompt_eval",
        "fixtures",
        "qwen_router_prompt_eval_cases.json"
      ])

    cases =
      path
      |> ArtifactIO.load_json!()
      |> Map.fetch!("cases")
      |> maybe_filter_cases(selected_ids)

    if is_integer(max_cases) and max_cases > 0, do: Enum.take(cases, max_cases), else: cases
  end

  defp maybe_filter_cases(cases, []), do: cases

  defp maybe_filter_cases(cases, selected_ids) do
    selected = MapSet.new(selected_ids)
    Enum.filter(cases, &(Map.fetch!(&1, "id") in selected))
  end

  defp case_messages(case_spec) do
    case_spec
    |> Map.fetch!("messages")
    |> Enum.map(fn message ->
      %{"role" => Map.get(message, "role"), "content" => Map.get(message, "content", "")}
    end)
  end

  defp expected_role_id(case_spec), do: get_in(case_spec, ["expected", "role_id"])

  defp timed(fun) when is_function(fun, 0) do
    start = System.monotonic_time(:microsecond)
    result = fun.()
    {System.monotonic_time(:microsecond) - start, result}
  end

  defp trajectory_margin(%Crucible.ForwardTrace{layer_trajectory: nil}), do: nil

  defp trajectory_margin(%Crucible.ForwardTrace{layer_trajectory: trajectory}) do
    case CrucibleSignalTrace.LayerTrajectory.cosine_drifts(trajectory) do
      {:ok, []} -> nil
      {:ok, drifts} -> drifts |> Enum.map(& &1.distance) |> Enum.max()
      {:error, _reason} -> nil
    end
  end

  defp trajectory_margins(rows) do
    rows
    |> Enum.map(& &1.trajectory_margin)
    |> Enum.filter(&is_number/1)
    |> case do
      [] ->
        %{min: nil, max: nil, mean: nil}

      values ->
        %{min: Enum.min(values), max: Enum.max(values), mean: Enum.sum(values) / length(values)}
    end
  end

  defp ratio(_count, 0), do: 1.0
  defp ratio(count, total), do: count / total

  defp pct(value) when is_number(value),
    do: :erlang.float_to_binary(value * 100.0, decimals: 2) <> "%"

  defp initial_messages(message), do: [%{"role" => "user", "content" => message}]

  defp token_count(messages) do
    messages
    |> Enum.map_join(" ", &to_string(Map.get(&1, "content", Map.get(&1, :content, ""))))
    |> String.split()
    |> length()
  end

  defp receipt_text(nil), do: ""

  defp receipt_text(receipt) do
    receipt.metadata[:text] || receipt.metadata["text"] || inspect(receipt)
  end

  defp mock_response(turn), do: "Result turn #{turn}: 6 * 7 = 42."

  defp role_name(0), do: "Worker"
  defp role_name(1), do: "Thinker"
  defp role_name(2), do: "Verifier"
  defp role_name(other), do: "role:#{other}"

  defp short_logits(%Nx.Tensor{} = logits), do: logits |> Nx.to_flat_list() |> Enum.take(5)
  defp short_logits(logits) when is_list(logits), do: Enum.take(logits, 5)
  defp short_logits(other), do: other

  defp parse_trace_content("full"), do: :full
  defp parse_trace_content(:full), do: :full
  defp parse_trace_content(_), do: :hash

  defp start_app!, do: Mix.Task.run("app.start")

  defp banner(label) do
    Mix.shell().info("")
    Mix.shell().info("=== #{label} ===")
  end

  defp kv(label, value), do: Mix.shell().info("  #{label}: #{format_value(value)}")

  defp pass(label), do: Mix.shell().info("PASS #{label}")

  defp print_payload(payload), do: Mix.shell().info(inspect(payload, pretty: true))

  defp format_value(value) when is_binary(value), do: value
  defp format_value(value), do: inspect(value)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp boolish(value) when is_boolean(value), do: value

  defp boolish(value) when is_binary(value),
    do: (value |> String.trim() |> String.downcase()) in ["1", "true", "yes"]

  defp boolish(value), do: not is_nil(value) and value != false

  defp require_crucible_live! do
    unless Application.get_env(:trinity_ops, :crucible_live_enabled?, false) do
      Mix.raise("Set TRINITY_CRUCIBLE_LIVE=true to run --live")
    end
  end

  defp generated_ref(prefix), do: "#{prefix}:#{System.unique_integer([:positive])}"

  defp tail_bytes(binary, n) when is_binary(binary) and byte_size(binary) > n do
    binary_part(binary, byte_size(binary) - n, n)
  end

  defp tail_bytes(binary, _n), do: binary

  defp normalize_for_json(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> normalize_for_json()
  end

  defp normalize_for_json(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {normalize_json_key(key), normalize_for_json(item)} end)
  end

  defp normalize_for_json(value) when is_list(value), do: Enum.map(value, &normalize_for_json/1)
  defp normalize_for_json(value) when is_tuple(value), do: Tuple.to_list(value)
  defp normalize_for_json(value) when is_boolean(value), do: value
  defp normalize_for_json(nil), do: nil
  defp normalize_for_json(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_for_json(value), do: value

  defp normalize_json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_json_key(key), do: key
end
