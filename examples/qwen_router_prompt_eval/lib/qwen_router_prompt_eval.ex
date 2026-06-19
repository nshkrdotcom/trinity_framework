defmodule Trinity.Examples.QwenRouterPromptEval do
  @moduledoc """
  Prompt-route evaluator for the standalone TRINITY single-node runtime.
  """

  require Logger

  alias SelfHostedInferenceBumblebee.Runtime.Profile
  alias Trinity.Bridge.Trace.JsonlSink
  alias Trinity.Coordinator.{ReflexPolicy, RoleInjector, TraceEvent}
  alias Trinity.Examples.QwenRouterPromptEval.SnapshotResolver
  alias Trinity.SingleNode

  @agent_names %{
    0 => "gpt-5",
    1 => "claude-sonnet-4-20250514",
    2 => "gemini-2.5-pro",
    3 => "deepseek-ai/DeepSeek-R1-Distill-Qwen-32B",
    4 => "google/gemma-3-27b-it",
    5 => "Qwen/Qwen3-32B (reasoning)",
    6 => "Qwen/Qwen3-32B (direct)"
  }

  @profiles ~w(cuda_exla host_exla binary mock_tiny emlx emily custom)a
  @profile_names Map.new(@profiles, &{Atom.to_string(&1), &1})
  @default_profile :cuda_exla
  @native_log_path "tmp/examples/qwen_router_prompt_eval.native.log"

  @spec main([String.t()]) :: :ok
  def main(argv) do
    argv = normalize_argv(argv)
    maybe_reexec_with_suppressed_stderr!(argv)

    unless "--debug-native-logs" in argv do
      Logger.configure(level: :error)
    end

    {opts, rest, errors} =
      OptionParser.parse(argv,
        strict: [
          artifact_dir: :string,
          case: :keep,
          debug_native_logs: :boolean,
          determinism_runs: :integer,
          list_cases: :boolean,
          min_agent_margin: :float,
          min_role_margin: :float,
          no_assert: :boolean,
          reflex_high_agent_margin: :float,
          reflex_high_role_margin: :float,
          reflex_low_agent_margin: :float,
          reflex_low_role_margin: :float,
          reflex_margin_mode: :string,
          reflex_report: :boolean,
          reflex_trace_out: :string,
          runtime_profile: :string,
          show_logits: :boolean,
          snapshot: :string,
          snapshot_out: :string,
          trace_out: :string,
          suppress_native_logs_child: :boolean,
          verbose: :boolean
        ]
      )

    unless rest == [], do: raise(ArgumentError, "unexpected arguments: #{inspect(rest)}")
    unless errors == [], do: raise(ArgumentError, "invalid options: #{inspect(errors)}")

    if Keyword.get(opts, :list_cases, false), do: list_cases(), else: run_eval!(opts)
  end

  defp maybe_reexec_with_suppressed_stderr!(argv) do
    cond do
      "--suppress-native-logs-child" in argv ->
        :ok

      "--list-cases" in argv ->
        :ok

      "--debug-native-logs" in argv ->
        :ok

      true ->
        File.mkdir_p!(Path.dirname(@native_log_path))
        File.rm(@native_log_path)

        shell = """
        stderr_path=$1
        script_path=$2
        shift 2
        mix run "$script_path" -- --suppress-native-logs-child "$@" 2>"$stderr_path"
        """

        {_output, status} =
          System.cmd("sh", ["-c", shell, "sh", @native_log_path, script_path() | argv],
            into: IO.stream(:stdio, :line)
          )

        if status != 0 do
          IO.puts(:stderr, "\nqwen_router_prompt_eval failed.")
          IO.puts(:stderr, "Native/framework logs were captured at #{@native_log_path}.")
          IO.puts(:stderr, "Re-run with --debug-native-logs to see them inline.\n")
          print_stderr_tail(@native_log_path)
        end

        System.halt(status)
    end
  end

  defp print_stderr_tail(path) do
    if File.exists?(path) do
      path
      |> File.read!()
      |> String.split("\n")
      |> Enum.reject(&(&1 == ""))
      |> Enum.take(-40)
      |> case do
        [] ->
          :ok

        lines ->
          IO.puts(:stderr, "Last stderr lines:")
          Enum.each(lines, &IO.puts(:stderr, &1))
      end
    end
  end

  defp run_eval!(opts) do
    Application.ensure_all_started(:trinity_single_node)

    profile = runtime_profile!(Keyword.get(opts, :runtime_profile))
    profile_default_margins = Profile.resolve(profile) |> Profile.default_margins()
    artifact_dir = Keyword.get(opts, :artifact_dir, default_artifact_dir())
    maybe_ensure_manifest!(profile, artifact_dir)

    cases = select_cases!(Keyword.get_values(opts, :case))
    snapshot = snapshot(profile, Keyword.get(opts, :snapshot))
    assert? = profile != :mock_tiny and not Keyword.get(opts, :no_assert, false)
    show_logits? = Keyword.get(opts, :show_logits, false)
    verbose? = Keyword.get(opts, :verbose, false) or show_logits?
    determinism_runs = max(1, Keyword.get(opts, :determinism_runs, 1))
    trace_out = Keyword.get(opts, :trace_out)
    reflex_trace_out = Keyword.get(opts, :reflex_trace_out)
    validate_trace_paths!(trace_out, reflex_trace_out)
    prepare_trace_out(trace_out)
    prepare_trace_out(reflex_trace_out)

    {:ok, runtime} =
      SingleNode.load_runtime(
        runtime_profile: profile,
        artifact_root: artifact_dir,
        messages: []
      )

    IO.puts("""

    === QWEN ROUTER PROMPT EVAL ===

    Artifact
      #{artifact_dir}

    Runtime profile
      #{profile}

    Native logs
      hidden in normal mode: #{@native_log_path}
      use --debug-native-logs to print XLA/CUDA compiler logs inline
    """)

    results =
      cases
      |> Enum.with_index(1)
      |> Enum.map(fn {case_spec, index} ->
        route_case!(runtime, case_spec, index, length(cases), assert?, show_logits?, verbose?,
          artifact_dir: artifact_dir,
          profile: profile,
          min_agent_margin: Keyword.get(opts, :min_agent_margin, profile_default_margins.agent),
          min_role_margin: Keyword.get(opts, :min_role_margin, profile_default_margins.role),
          snapshot: snapshot
        )
      end)

    results = maybe_attach_reflex!(results, opts, reflex_trace_out)

    determinism_failures =
      maybe_verify_determinism!(runtime, cases, results, determinism_runs,
        artifact_dir: artifact_dir,
        profile: profile
      )

    write_outputs!(results, opts, profile, trace_out, reflex_trace_out)
    maybe_print_reflex_report(results, opts)
    finish_eval!(results, determinism_failures)
  end

  defp maybe_attach_reflex!(results, opts, reflex_trace_out) do
    if Keyword.get(opts, :reflex_report, false) or is_binary(reflex_trace_out),
      do: Enum.map(results, &attach_reflex!(&1, reflex_options!(opts))),
      else: results
  end

  defp maybe_verify_determinism!(_runtime, _cases, _results, runs, _opts) when runs <= 1,
    do: []

  defp maybe_verify_determinism!(runtime, cases, results, runs, opts),
    do: verify_determinism!(runtime, cases, results, runs, opts)

  defp write_outputs!(results, opts, profile, trace_out, reflex_trace_out) do
    if path = Keyword.get(opts, :snapshot_out), do: write_snapshot!(results, path)
    if path = trace_out, do: write_trace!(results, path, profile)
    if path = reflex_trace_out, do: write_reflex_trace!(results, path, profile)
  end

  defp maybe_print_reflex_report(results, opts) do
    if Keyword.get(opts, :reflex_report, false), do: print_reflex_report(results)
  end

  defp finish_eval!(results, determinism_failures) do
    failures =
      Enum.filter(results, &(&1.status == :fail)) ++
        Enum.map(determinism_failures, fn id -> %{id: id, status: :fail} end)

    if failures == [] do
      print_summary(results)
    else
      ids = Enum.map_join(failures, ", ", & &1.id)
      raise "qwen_router_prompt_eval failed cases=#{ids}"
    end
  end

  defp route_case!(runtime, case_spec, index, total, assert?, show_logits?, verbose?, opts) do
    {:ok, result} =
      SingleNode.route(case_spec.messages,
        runtime: runtime,
        runtime_profile: opts[:profile],
        artifact_root: opts[:artifact_dir],
        trace_ref: "qwen-router-prompt-eval:#{case_spec.id}",
        coordination_run_ref: "qwen-router-prompt-eval:#{case_spec.id}"
      )

    decision = result.decision
    logits = result.logits
    expected = case_spec.expected
    agent_margin = margin(logits.margins, :agent)
    role_margin = margin(logits.margins, :role)

    status =
      route_status(case_spec.id, decision, expected,
        assert?: assert?,
        agent_margin: agent_margin,
        min_agent_margin: opts[:min_agent_margin],
        role_margin: role_margin,
        min_role_margin: opts[:min_role_margin],
        snapshot: opts[:snapshot]
      )

    print_case(case_spec, result, index, total, status, show_logits?, verbose?)

    %{
      id: case_spec.id,
      status: status,
      expected_role_id: expected.role_id,
      expected_agent_id: expected.agent_id,
      role_id: decision.selected_role_id,
      agent_id: decision.selected_agent_id,
      agent_margin: agent_margin,
      role_margin: role_margin,
      agent_logits_rounded: Enum.map(logits.agent_logits || [], &Float.round(&1, 6)),
      role_logits_rounded: Enum.map(logits.role_logits || [], &Float.round(&1, 6)),
      token_count: decision.token_count,
      transcript_hash: decision.transcript_hash,
      route_hash: decision.route_hash,
      confidence_band: decision.confidence_band,
      role_name: decision.role_name,
      runtime_profile: opts[:profile],
      artifact_identity: decision.artifact_identity
    }
  end

  defp prepare_trace_out(nil), do: :ok

  defp prepare_trace_out(path) when is_binary(path) do
    File.mkdir_p!(Path.dirname(path))
    File.rm(path)
    :ok
  end

  defp validate_trace_paths!(path, path) when is_binary(path) do
    raise ArgumentError, "--trace-out and --reflex-trace-out must use different paths"
  end

  defp validate_trace_paths!(_trace_out, _reflex_trace_out), do: :ok

  defp write_trace!(results, path, profile) do
    Enum.each(results, fn result ->
      run_ref = "qwen-router-prompt-eval:#{result.id}"

      eval_payload = %{
        turn: 0,
        case_id: result.id,
        expected_agent_id: result.expected_agent_id,
        expected_role_id: result.expected_role_id,
        actual_agent_id: result.agent_id,
        actual_role_id: result.role_id,
        status: result.status,
        agent_margin: result.agent_margin,
        role_margin: result.role_margin,
        token_count: result.token_count,
        transcript_hash: result.transcript_hash,
        route_hash: result.route_hash
      }

      :ok = emit_trace_event(path, run_ref, :route_decision, route_payload(result, profile))
      :ok = emit_trace_event(path, run_ref, :route_eval_result, eval_payload)
    end)

    :ok
  end

  defp write_reflex_trace!(results, path, profile) do
    Enum.each(results, fn result ->
      run_ref = "qwen-router-prompt-eval:#{result.id}"
      reflex = Map.fetch!(result, :reflex)

      reflex_payload = %{
        turn: 0,
        case_id: result.id,
        route_hash: result.route_hash,
        selected_agent_id: result.agent_id,
        selected_role_id: result.role_id,
        original_role_name: result.role_name,
        original_role_atom: RoleInjector.role_atom(result.role_id),
        confidence_class: reflex.confidence_class,
        action: reflex.action,
        reason: reflex.reason,
        agent_margin: reflex.agent_margin,
        role_margin: reflex.role_margin,
        min_margin: reflex.min_margin,
        confidence_band: reflex.confidence_band,
        thresholds: reflex.thresholds,
        forced_sequence: reflex.forced_sequence,
        next_role_override: reflex.next_role_override,
        reflex_enabled: reflex.enabled?
      }

      :ok = emit_trace_event(path, run_ref, :route_decision, route_payload(result, profile))
      :ok = emit_trace_event(path, run_ref, :reflex_decision, reflex_payload)
    end)

    :ok
  end

  defp route_payload(result, profile) do
    identity = result.artifact_identity || %{}

    %{
      turn: 0,
      case_id: result.id,
      selected_agent_id: result.agent_id,
      selected_role_id: result.role_id,
      role_name: result.role_name,
      agent_margin: result.agent_margin,
      role_margin: result.role_margin,
      min_margin: min(result.agent_margin, result.role_margin),
      confidence_band: result.confidence_band,
      token_count: result.token_count,
      transcript_hash: result.transcript_hash,
      input_hash: result.transcript_hash,
      route_hash: result.route_hash,
      runtime_profile: safe_runtime_profile(result.runtime_profile, profile),
      provider_pool: nil,
      route_path: :qwen_router_prompt_eval,
      artifact_ref: identity_field(identity, :artifact_ref),
      artifact_revision: identity_field(identity, :artifact_revision),
      artifact_hash_ref:
        identity_field(identity, :artifact_manifest_sha256_actual) ||
          identity_field(identity, :artifact_manifest_sha256)
    }
  end

  defp attach_reflex!(result, opts) do
    route = %{
      margins: %{agent: result.agent_margin, role: result.role_margin},
      confidence_band: result.confidence_band,
      runtime_profile: safe_runtime_profile(result.runtime_profile, nil),
      selected_role_id: result.role_id,
      role_name: result.role_name,
      role_atom: RoleInjector.role_atom(result.role_id)
    }

    case ReflexPolicy.evaluate(route, opts) do
      {:ok, reflex} -> Map.put(result, :reflex, reflex)
      {:error, reason} -> raise ArgumentError, "invalid reflex options: #{inspect(reason)}"
    end
  end

  defp reflex_options!(opts) do
    [
      reflex_enabled?: true,
      reflex_margin_mode:
        reflex_margin_mode!(Keyword.get(opts, :reflex_margin_mode, "profile_floor")),
      reflex_high_agent_margin: Keyword.get(opts, :reflex_high_agent_margin),
      reflex_high_role_margin: Keyword.get(opts, :reflex_high_role_margin),
      reflex_low_agent_margin: Keyword.get(opts, :reflex_low_agent_margin),
      reflex_low_role_margin: Keyword.get(opts, :reflex_low_role_margin),
      reflex_missing_margin: :medium,
      reflex_force_sequence: [:thinker, :verifier]
    ]
  end

  defp reflex_margin_mode!("profile_floor"), do: :profile_floor
  defp reflex_margin_mode!(:profile_floor), do: :profile_floor
  defp reflex_margin_mode!("absolute"), do: :absolute
  defp reflex_margin_mode!(:absolute), do: :absolute

  defp reflex_margin_mode!(value),
    do: raise(ArgumentError, "invalid reflex margin mode: #{inspect(value)}")

  defp emit_trace_event(path, run_ref, event_type, payload) do
    JsonlSink.emit(
      %TraceEvent{
        event_ref: "trace-event:#{event_type}:#{run_ref}",
        event_type: event_type,
        trace_ref: run_ref,
        coordination_run_ref: run_ref,
        payload: payload
      },
      path: path,
      content: :hash,
      include_refs: true
    )
  end

  defp identity_field(identity, key) when is_map(identity),
    do: Map.get(identity, key, Map.get(identity, Atom.to_string(key)))

  defp safe_runtime_profile(profile, _fallback) when profile in @profiles, do: profile
  defp safe_runtime_profile(profile, _fallback) when is_binary(profile), do: profile
  defp safe_runtime_profile(_profile, fallback), do: fallback

  defp route_status(id, decision, expected, opts) do
    if Keyword.fetch!(opts, :assert?) do
      asserted_route_status(id, decision, expected, opts)
    else
      :report
    end
  end

  defp asserted_route_status(id, decision, expected, opts) do
    cond do
      decision.selected_agent_id != expected.agent_id -> :fail
      decision.selected_role_id != expected.role_id -> :fail
      not margin_ok?(opts[:agent_margin], opts[:min_agent_margin]) -> :fail
      not margin_ok?(opts[:role_margin], opts[:min_role_margin]) -> :fail
      not snapshot_ok?(id, decision, opts[:snapshot]) -> :fail
      true -> :ok
    end
  end

  defp verify_determinism!(runtime, cases, baseline_results, runs, opts) do
    baseline = Map.new(baseline_results, fn result -> {result.id, result.route_hash} end)

    Enum.reduce(2..runs, [], fn run_index, mismatches ->
      Enum.reduce(
        cases,
        mismatches,
        &determinism_mismatch(runtime, baseline, run_index, opts, &1, &2)
      )
    end)
  end

  defp determinism_mismatch(runtime, baseline, run_index, opts, case_spec, acc) do
    run_ref = "qwen-router-prompt-eval:#{case_spec.id}"

    {:ok, result} =
      SingleNode.route(case_spec.messages,
        runtime: runtime,
        runtime_profile: opts[:profile],
        artifact_root: opts[:artifact_dir],
        trace_ref: run_ref,
        coordination_run_ref: run_ref
      )

    if baseline[case_spec.id] == result.decision.route_hash do
      acc
    else
      IO.puts("  determinism mismatch case=#{case_spec.id} run=#{run_index}")
      [case_spec.id | acc]
    end
  end

  defp list_cases do
    Enum.each(all_cases(), fn case_spec -> IO.puts(case_spec.id) end)
  end

  defp select_cases!([]), do: all_cases()

  defp select_cases!(ids) do
    cases_by_id = Map.new(all_cases(), &{&1.id, &1})

    Enum.map(ids, fn id ->
      Map.get(cases_by_id, id) || raise("Unknown case #{inspect(id)}. Run with --list-cases.")
    end)
  end

  defp all_cases do
    {cases, _coverage} = load_cases!()
    cases
  end

  defp load_cases! do
    doc =
      fixtures_path("qwen_router_prompt_eval_cases.json")
      |> File.read!()
      |> Jason.decode!()

    cases =
      Enum.map(doc["cases"], fn case_spec ->
        %{
          id: case_spec["id"],
          tags: case_spec["tags"] || [],
          notes: case_spec["notes"],
          expected: %{
            agent_id: case_spec["expected"]["agent_id"],
            role_id: case_spec["expected"]["role_id"]
          },
          messages:
            Enum.map(case_spec["messages"], fn message ->
              %{role: message["role"], content: message["content"]}
            end)
        }
      end)

    {cases, doc["coverage"] || %{}}
  end

  defp snapshot(profile, explicit_path) do
    case SnapshotResolver.resolve(profile, explicit_path) do
      nil -> nil
      path -> path |> File.read!() |> Jason.decode!()
    end
  end

  defp snapshot_ok?(_id, _decision, nil), do: true

  defp snapshot_ok?(id, decision, snapshot) do
    expected = Enum.find(snapshot["cases"] || [], &(&1["id"] == id))

    is_nil(expected) or
      (expected["agent_id"] == decision.selected_agent_id and
         expected["role_id"] == decision.selected_role_id and
         expected["token_count"] == decision.token_count and
         expected["transcript_hash"] == decision.transcript_hash)
  end

  defp print_case(case_spec, result, index, total, status, show_logits?, verbose?) do
    decision = result.decision
    logits = result.logits
    expected = case_spec.expected

    IO.puts("""

    [#{index}/#{total}] #{case_spec.id} - #{status_label(status)}

    Expected route:
      agent #{expected.agent_id}: #{Map.fetch!(@agent_names, expected.agent_id)}
      role  #{expected.role_id}: #{RoleInjector.role_name(expected.role_id)}

    Router returned:
      agent #{decision.selected_agent_id}: #{Map.fetch!(@agent_names, decision.selected_agent_id)}
      role  #{decision.selected_role_id}: #{RoleInjector.role_name(decision.selected_role_id)}

    Router input tokens: #{decision.token_count}
    """)

    if verbose? do
      IO.puts("""
      Debug:
        transcript_hash: #{decision.transcript_hash}
        route_hash: #{decision.route_hash}
        agent_margin: #{format_float(margin(logits.margins, :agent))}
        role_margin: #{format_float(margin(logits.margins, :role))}
      """)
    end

    if show_logits? do
      IO.puts("      agent_logits: #{inspect(round_list(logits.agent_logits || []))}")
      IO.puts("      role_logits: #{inspect(round_list(logits.role_logits || []))}")
    end
  end

  defp print_summary(results) do
    passed = Enum.count(results, &(&1.status in [:ok, :report]))
    failed = Enum.count(results, &(&1.status == :fail))

    role_counts =
      results
      |> Enum.frequencies_by(& &1.role_id)
      |> Enum.sort()
      |> Enum.map_join(", ", fn {role_id, count} ->
        "#{RoleInjector.role_name(role_id)}=#{count}"
      end)

    agent_counts =
      results
      |> Enum.frequencies_by(& &1.agent_id)
      |> Enum.sort()
      |> Enum.map_join(", ", fn {agent_id, count} -> "#{agent_id}=#{count}" end)

    IO.puts("""

    Summary
      passed: #{passed}
      failed: #{failed}
      roles selected: #{role_counts}
      agent slots selected: #{agent_counts}

    PASS qwen_router_prompt_eval
    """)
  end

  defp print_reflex_report(results) do
    IO.puts("\nReflex classification")

    Enum.each(results, fn result ->
      reflex = Map.fetch!(result, :reflex)
      IO.puts("  #{result.id}: #{reflex.confidence_class} -> #{reflex.action}")
    end)

    class_counts = Enum.frequencies_by(results, & &1.reflex.confidence_class)
    action_counts = Enum.frequencies_by(results, & &1.reflex.action)

    IO.puts("\nReflex summary")
    IO.puts("  high: #{Map.get(class_counts, :high, 0)}")
    IO.puts("  medium: #{Map.get(class_counts, :medium, 0)}")
    IO.puts("  low: #{Map.get(class_counts, :low, 0)}")
    IO.puts("  direct_dispatch: #{Map.get(action_counts, :direct_dispatch, 0)}")
    IO.puts("  normal_dispatch: #{Map.get(action_counts, :normal_dispatch, 0)}")

    IO.puts("  thinker_then_verifier: #{Map.get(action_counts, :thinker_then_verifier, 0)}")
  end

  defp write_snapshot!(results, path) do
    File.mkdir_p!(Path.dirname(path))

    payload = %{
      "schema_version" => 1,
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "cases" =>
        Enum.map(results, fn result ->
          %{
            "id" => result.id,
            "agent_id" => result.agent_id,
            "role_id" => result.role_id,
            "token_count" => result.token_count,
            "agent_margin" => result.agent_margin,
            "role_margin" => result.role_margin,
            "agent_logits_rounded" => result.agent_logits_rounded,
            "role_logits_rounded" => result.role_logits_rounded,
            "transcript_hash" => result.transcript_hash,
            "route_hash" => result.route_hash
          }
        end)
    }

    File.write!(path, Jason.encode!(payload, pretty: true))
    IO.puts("\nSnapshot written: #{path} (#{length(results)} cases)")
  end

  defp maybe_ensure_manifest!(:mock_tiny, _artifact_dir), do: :ok

  defp maybe_ensure_manifest!(_profile, artifact_dir) do
    path = Path.join(artifact_dir, "manifest.json")
    unless File.exists?(path), do: raise("Missing adapted artifact manifest: #{path}")
  end

  defp margin(nil, _key), do: nil
  defp margin(margins, key), do: Map.get(margins, key, Map.get(margins, Atom.to_string(key)))

  defp margin_ok?(_margin, nil), do: true
  defp margin_ok?(:infinity, _min), do: true
  defp margin_ok?(margin, min) when is_number(margin) and is_number(min), do: margin >= min
  defp margin_ok?(_margin, _min), do: false

  defp status_label(:ok), do: "PASS"
  defp status_label(:fail), do: "FAIL"
  defp status_label(:report), do: "REPORT ONLY"

  defp round_list(values) do
    Enum.map(values, fn
      value when is_float(value) -> Float.round(value, 5)
      value -> value
    end)
  end

  defp format_float(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 5)
  defp format_float(value), do: inspect(value)

  defp runtime_profile!(nil), do: @default_profile

  defp runtime_profile!(value) when is_binary(value) do
    case Map.fetch(@profile_names, value) do
      {:ok, profile} -> profile
      :error -> raise("Unknown runtime profile #{inspect(value)}")
    end
  end

  defp runtime_profile!(profile) when profile in @profiles, do: profile

  defp default_artifact_dir do
    Path.expand(
      "../../../priv/sakana_trinity/adapted_qwen3_0_6b_layer26",
      __DIR__
    )
  end

  defp script_path, do: Path.expand("qwen_router_prompt_eval.exs", __DIR__)

  defp fixtures_path(file), do: Path.expand("../fixtures/#{file}", __DIR__)

  defp normalize_argv(["--" | rest]), do: rest
  defp normalize_argv(argv), do: argv
end
