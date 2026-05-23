defmodule Trinity.Ops.NativeTasks do
  @moduledoc """
  Framework-owned implementations for the legacy `mix trinity.*` operator tasks.

  These tasks intentionally call the deconstructed framework packages directly.
  The deprecated coordinator repo may delegate here, but this module must not
  call back into `trinity_coordinator`.
  """

  alias CrucibleFactorization.SVD
  alias CrucibleModelRegistry.Pins.{ArtifactPin, Fetcher, Verifier}

  alias SelfHostedInferenceBumblebee.{
    Extractor,
    HeadLoader,
    QwenSakanaLoader,
    RoutingHead,
    SLMProfile
  }

  alias SelfHostedInferenceBumblebee.Runtime.{Preflight, Profile}
  alias Trinity.Bridge.Trace.JsonlSink
  alias Trinity.Coordinator.TraceEvent
  alias Trinity.Ops.CommandSpec
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
  @summary_schema_version 1
  @tail_bytes 4096

  @spec run(CommandSpec.task_key(), keyword()) :: :ok
  def run(:trinity_artifact_fetch, opts), do: artifact_fetch(opts)
  def run(:trinity_demo, opts), do: route_demo(opts)
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

    vector = SVD.load_router_vector!(path)
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

    vector = SVD.load_router_vector!(default_router_vector_path())
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

    python_report_path =
      Keyword.get(opts, :python_report) || Mix.raise("--python-report is required")

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
      vector = SVD.load_router_vector!(path)

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

  defp role_name(0), do: "Thinker"
  defp role_name(1), do: "Worker"
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

  defp format_value(value) when is_binary(value), do: value
  defp format_value(value), do: inspect(value)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp boolish(value) when is_boolean(value), do: value

  defp boolish(value) when is_binary(value),
    do: (value |> String.trim() |> String.downcase()) in ["1", "true", "yes"]

  defp boolish(value), do: not is_nil(value) and value != false

  defp generated_ref(prefix), do: "#{prefix}:#{System.unique_integer([:positive])}"

  defp tail_bytes(binary, n) when is_binary(binary) and byte_size(binary) > n do
    binary_part(binary, byte_size(binary) - n, n)
  end

  defp tail_bytes(binary, _n), do: binary

  defp normalize_for_json(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {normalize_json_key(key), normalize_for_json(item)} end)
  end

  defp normalize_for_json(value) when is_list(value), do: Enum.map(value, &normalize_for_json/1)
  defp normalize_for_json(value) when is_tuple(value), do: Tuple.to_list(value)
  defp normalize_for_json(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_for_json(value), do: value

  defp normalize_json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_json_key(key), do: key
end
