defmodule Trinity.Ops.Tasks do
  @moduledoc """
  Dispatch layer for the `mix trinity.*` task modules.
  """

  alias SelfHostedInferenceBumblebee.Runtime.Preflight
  alias Trinity.Ops.{CommandSpec, Gates, NativeTasks, OrchestratorRunner}
  alias Trinity.Sakana.FitnessExporter

  @spec run(CommandSpec.task_key(), [String.t()]) :: :ok
  def run(:trinity_gates, argv), do: Gates.run(argv)

  def run(:trinity_env_check, argv) do
    opts = CommandSpec.parse!(:trinity_env_check, argv)
    artifact_dir = Keyword.get(opts, :artifact_dir)

    if artifact_dir && not File.dir?(artifact_dir) do
      Mix.raise("artifact directory does not exist: #{artifact_dir}")
    end

    Enum.each(Keyword.get_values(opts, :require), &check_requirement!/1)
    Mix.shell().info("trinity.env.check: ok")
  end

  def run(:trinity_orchestrator_demo, argv) do
    opts = CommandSpec.parse!(:trinity_orchestrator_demo, argv)

    case OrchestratorRunner.run(opts) do
      {:ok, summary} -> print_summary(summary, Keyword.get(opts, :json, false))
      {:error, reason} -> Mix.raise("trinity.orchestrator.demo failed: #{inspect(reason)}")
    end
  end

  def run(:trinity_sakana_fitness_export, argv) do
    opts = CommandSpec.parse!(:trinity_sakana_fitness_export, argv)
    traces = Keyword.get_values(opts, :trace)
    dry_run? = Keyword.get(opts, :dry_run, false)

    cond do
      traces == [] ->
        Mix.raise("trinity.sakana.fitness_export requires at least one --trace")

      is_nil(Keyword.get(opts, :out)) and not dry_run? ->
        Mix.raise("trinity.sakana.fitness_export requires --out unless --dry-run is used")

      Keyword.get(opts, :format, "jsonl") != "jsonl" ->
        Mix.raise("trinity.sakana.fitness_export supports only --format jsonl")

      true ->
        run_fitness_export(traces, opts)
    end
  end

  def run(task_key, argv) do
    task_key
    |> CommandSpec.parse!(argv)
    |> then(&NativeTasks.run(task_key, &1))
  end

  defp check_requirement!("cuda") do
    Preflight.require_cuda!()
    :ok
  end

  defp check_requirement!("artifact"), do: :ok
  defp check_requirement!(other), do: Mix.raise("unknown environment requirement: #{other}")

  defp print_summary(summary, true), do: IO.puts(Jason.encode!(summary))

  defp print_summary(summary, false) do
    Mix.shell().info("TRINITY Orchestrator demo: PASS")
    Mix.shell().info("Trace: #{summary.trace_path}")
    Mix.shell().info("Reflex decisions: #{summary.reflex_decisions}")
    Mix.shell().info("Direct dispatch: #{summary.direct_dispatch_count}")
    Mix.shell().info("Normal dispatch: #{summary.normal_dispatch_count}")
    Mix.shell().info("Thinker then Verifier: #{summary.thinker_then_verifier_count}")
    :ok
  end

  defp run_fitness_export(traces, opts) do
    export_opts =
      opts
      |> Keyword.delete(:trace)
      |> Keyword.put(:content, content_mode(Keyword.get(opts, :content, "hash")))
      |> Keyword.put(:margin_mode, margin_mode(Keyword.get(opts, :margin_mode, "profile_floor")))

    case FitnessExporter.export(traces, export_opts) do
      {:ok, summary} -> print_fitness_summary(summary, Keyword.get(opts, :json, false))
      {:error, reason} -> Mix.raise("trinity.sakana.fitness_export failed: #{inspect(reason)}")
    end
  end

  defp print_fitness_summary(summary, true), do: IO.puts(Jason.encode!(summary))

  defp print_fitness_summary(summary, false) do
    Mix.shell().info("TRINITY Sakana fitness export: PASS")
    Mix.shell().info("Records: #{summary.record_count}")
    Mix.shell().info("Dataset digest: #{summary.dataset_digest}")
    :ok
  end

  defp content_mode("full"), do: :full
  defp content_mode("hash"), do: :hash
  defp content_mode(other), do: Mix.raise("unsupported fitness content mode: #{inspect(other)}")

  defp margin_mode("profile_floor"), do: :profile_floor
  defp margin_mode("absolute"), do: :absolute
  defp margin_mode(other), do: Mix.raise("unsupported fitness margin mode: #{inspect(other)}")
end
