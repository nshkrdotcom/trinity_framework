defmodule Trinity.Ops.CommandSpec do
  @moduledoc """
  Parser contract for the operator-visible `mix trinity.*` task surface.
  """

  @type task_key :: atom()

  @spec all() :: %{task_key() => map()}
  def all do
    %{
      trinity_artifact_fetch: %{
        task: "trinity.artifact.fetch",
        switches: [pin: :string, dest: :string, offline: :boolean, help: :boolean]
      },
      trinity_demo: %{
        task: "trinity.demo",
        switches: route_demo_switches()
      },
      trinity_env_check: %{
        task: "trinity.env.check",
        switches: [artifact_dir: :string, require: :string],
        aliases: [a: :artifact_dir, r: :require]
      },
      trinity_eval: %{
        task: "trinity.eval",
        switches: eval_switches(),
        positional: true
      },
      trinity_crucible_inspect: %{
        task: "trinity.crucible.inspect",
        switches: crucible_switches()
      },
      trinity_crucible_matrix_eval: %{
        task: "trinity.crucible.matrix_eval",
        switches: crucible_matrix_switches()
      },
      trinity_crucible_transcript: %{
        task: "trinity.crucible.transcript",
        switches: crucible_transcript_switches(),
        positional: true
      },
      trinity_gates: %{
        task: "trinity.gates",
        switches: [
          skip_docs: :boolean,
          fast: :boolean,
          include_parity_check: :boolean,
          python_report: :string,
          elixir_report: :string,
          include_hex_build: :boolean,
          summary_out: :string
        ]
      },
      trinity_orchestrator_demo: %{
        task: "trinity.orchestrator.demo",
        switches: [
          allow_live: :boolean,
          artifact_dir: :string,
          json: :boolean,
          max_estimated_cost_usd: :float,
          max_provider_calls: :integer,
          max_provider_latency_ms: :integer,
          max_turns: :integer,
          max_verifier_revisions: :integer,
          max_wall_time_ms: :integer,
          message: :string,
          mock_provider: :boolean,
          provider_pool: :string,
          run_id: :string,
          runtime_profile: :string,
          trace_content: :string,
          trace_out: :string
        ]
      },
      trinity_hitl_adapted: %{
        task: "trinity.hitl.adapted",
        switches: [
          artifact_dir: :string,
          runtime_profile: :string,
          compare_path: :string,
          message: :string
        ]
      },
      trinity_hitl_base_qwen: %{task: "trinity.hitl.base_qwen", switches: []},
      trinity_hitl_gpu: %{task: "trinity.hitl.gpu", switches: []},
      trinity_hitl_head_route: %{task: "trinity.hitl.head_route", switches: []},
      trinity_hitl_mock_loop: %{
        task: "trinity.hitl.mock_loop",
        switches: [
          artifact_dir: :string,
          runtime_profile: :string,
          max_turns: :integer,
          message: :string,
          trace_out: :string,
          trace_content: :string,
          run_id: :string
        ]
      },
      trinity_hitl_vector: %{task: "trinity.hitl.vector", switches: []},
      trinity_parity_check: %{
        task: "trinity.parity.check",
        switches: [
          python_report: :string,
          elixir_report: :string,
          strict_stage_tolerances: :boolean,
          strict_current_python: :boolean,
          strict_reference: :boolean,
          top_diffs: :integer,
          summary_out: :string,
          python: :string
        ]
      },
      trinity_route_demo: %{
        task: "trinity.route.demo",
        switches: route_demo_switches()
      },
      trinity_sakana_export_adapted: %{
        task: "trinity.sakana.export_adapted",
        switches: [
          out: :string,
          source_vector: :string,
          tensor_name: :string,
          profile: :string,
          resume: :boolean,
          force: :boolean,
          only_index: :integer,
          skip_existing: :boolean,
          dry_run: :boolean,
          svd_compute_type: :string,
          json: :boolean,
          runtime_profile: :string
        ]
      },
      trinity_sakana_fitness_export: %{
        task: "trinity.sakana.fitness_export",
        switches: [
          trace: :keep,
          out: :string,
          manifest_out: :string,
          report_out: :string,
          format: :string,
          content: :string,
          score_formula: :string,
          margin_mode: :string,
          margin_scale: :float,
          latency_target_ms: :integer,
          cost_target_usd: :float,
          positive_threshold: :float,
          negative_threshold: :float,
          skip_invalid: :boolean,
          dry_run: :boolean,
          json: :boolean
        ]
      },
      trinity_sakana_import_python: %{
        task: "trinity.sakana.import_python",
        switches: [
          source_dir: :string,
          manifest: :string,
          reference: :string,
          out: :string,
          force: :boolean,
          resume: :boolean,
          no_load_qwen: :boolean,
          json: :boolean
        ]
      },
      trinity_sakana_large_tensor_chunks: %{
        task: "trinity.sakana.large_tensor_chunks",
        switches: [
          out: :string,
          components_dir: :string,
          python_report: :string,
          stage_dir: :string,
          chunk_rows: :integer,
          source: :string,
          no_cuda: :boolean
        ]
      },
      trinity_sakana_parity_sample: %{
        task: "trinity.sakana.parity_sample",
        switches: [
          out: :string,
          components_dir: :string,
          python_report: :string,
          stage_dir: :string,
          router_vector: :string,
          reference: :string,
          no_cuda: :boolean,
          semantic_only: :boolean,
          host_semantic_only: :boolean,
          device_semantic_only: :boolean,
          preferred_layout_only: :boolean,
          source_from_python_stage: :boolean,
          all_selected_tensors: :boolean,
          selected_source_filter: :string,
          skip_native_svd: :boolean
        ]
      },
      trinity_sakana_router_trace: %{
        task: "trinity.sakana.router_trace",
        switches: [
          artifact_dir: :string,
          runtime_profile: :string,
          python_report: :string,
          out: :string,
          message: :string,
          hidden_max_abs: :float,
          hidden_mean_abs: :float,
          hidden_min_cosine: :float,
          hidden_max_relative_l2: :float,
          logits_max_abs: :float,
          logits_mean_abs: :float,
          logits_min_cosine: :float,
          logits_max_relative_l2: :float
        ]
      }
    }
  end

  @spec task_name!(task_key()) :: String.t()
  def task_name!(task_key), do: Map.fetch!(all(), task_key).task

  defp route_demo_switches do
    [
      allow_live: :boolean,
      artifact_dir: :string,
      runtime_profile: :string,
      governed_api_key: :string,
      governed_authority_ref: :string,
      governed_base_url: :string,
      governed_credential_ref: :string,
      governed_model: :string,
      governed_provider: :string,
      governed_provider_pool_ref: :string,
      governed_runtime_ref: :string,
      governed_workflow_ref: :string,
      max_turns: :integer,
      message: :string,
      mock: :boolean,
      mock_provider: :boolean,
      openai_api_key: :string,
      profile: :string,
      provider_pool: :string,
      run_id: :string,
      trace_content: :string,
      trace_out: :string
    ]
  end

  defp crucible_switches do
    [
      artifact_dir: :string,
      artifact_root: :string,
      runtime_profile: :string,
      message: :string,
      prompt: :string,
      trace: :string,
      live: :boolean,
      out: :string,
      trace_out: :string,
      model_id: :string,
      tokenizer_id: :string,
      backend: :string,
      architecture: :string,
      trace_name: :string,
      forward_timeout_ms: :integer
    ]
  end

  defp crucible_matrix_switches do
    [
      artifact_dir: :string,
      artifact_root: :string,
      runtime_profile: :string,
      case: :keep,
      out: :string,
      trace: :keep,
      live: :boolean,
      limit: :integer,
      no_assert: :boolean,
      max_cases: :integer,
      model_id: :string,
      tokenizer_id: :string,
      backend: :string,
      architecture: :string,
      forward_timeout_ms: :integer,
      run_tag: :string,
      stability_repeats: :integer,
      stability_prompt: :string
    ]
  end

  defp crucible_transcript_switches do
    [
      artifact_root: :string,
      cwd: :string,
      env: :keep,
      name: :string,
      phase: :string
    ]
  end

  defp eval_switches do
    [
      artifact_dir: :string,
      runtime_profile: :string,
      case: :keep,
      out: :string,
      no_assert: :boolean,
      max_cases: :integer
    ]
  end

  @spec parse!(task_key(), [String.t()]) :: keyword()
  def parse!(task_key, argv) do
    spec = Map.fetch!(all(), task_key)

    {opts, rest, invalid} =
      OptionParser.parse(argv,
        strict: Map.fetch!(spec, :switches),
        aliases: Map.get(spec, :aliases, [])
      )

    unless rest == [] or Map.get(spec, :positional, false) do
      raise(ArgumentError, "unexpected arguments: #{inspect(rest)}")
    end

    unless invalid == [], do: raise(ArgumentError, "invalid options: #{inspect(invalid)}")

    if Map.get(spec, :positional, false), do: Keyword.put(opts, :_args, rest), else: opts
  end
end
