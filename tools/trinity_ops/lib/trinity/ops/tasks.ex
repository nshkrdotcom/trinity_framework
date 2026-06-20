defmodule Trinity.Ops.Tasks do
  @moduledoc """
  Dispatch layer for the `mix trinity.*` task modules.
  """

  alias SelfHostedInferenceBumblebee.Runtime.Preflight
  alias Trinity.Coordinator.ReflexCalibration
  alias Trinity.Ops.{CommandSpec, Gates, NativeTasks, OrchestratorRunner}

  alias Trinity.Sakana.{
    CandidateEval,
    FitnessDatasetInspector,
    FitnessDatasetReader,
    FitnessExporter,
    FitnessReplay
  }

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

  def run(:trinity_sakana_fitness_inspect, argv) do
    opts = CommandSpec.parse!(:trinity_sakana_fitness_inspect, argv)
    fitness = required!(opts, :fitness, "trinity.sakana.fitness_inspect requires --fitness")

    case FitnessDatasetInspector.inspect(fitness,
           manifest: Keyword.get(opts, :manifest),
           skip_invalid: Keyword.get(opts, :skip_invalid, false)
         ) do
      {:ok, report} ->
        write_and_print_report(
          report,
          Keyword.get(opts, :out),
          Keyword.get(opts, :json, false),
          "TRINITY Sakana fitness inspect"
        )

      {:error, reason} ->
        Mix.raise("trinity.sakana.fitness_inspect failed: #{inspect(reason)}")
    end
  end

  def run(:trinity_sakana_fitness_replay, argv) do
    opts = CommandSpec.parse!(:trinity_sakana_fitness_replay, argv)
    fitness = required!(opts, :fitness, "trinity.sakana.fitness_replay requires --fitness")

    replay_opts =
      opts
      |> Keyword.put(:manifest, Keyword.get(opts, :manifest))
      |> Keyword.put(:margin_mode, margin_mode(Keyword.get(opts, :margin_mode, "profile_floor")))

    case FitnessReplay.replay(fitness, replay_opts) do
      {:ok, report} ->
        write_and_print_report(
          report,
          Keyword.get(opts, :out),
          Keyword.get(opts, :json, false),
          "TRINITY Sakana fitness replay"
        )

      {:error, reason} ->
        Mix.raise("trinity.sakana.fitness_replay failed: #{inspect(reason)}")
    end
  end

  def run(:trinity_reflex_calibrate, argv) do
    opts = CommandSpec.parse!(:trinity_reflex_calibrate, argv)
    fitness = required!(opts, :fitness, "trinity.reflex.calibrate requires --fitness")

    calibration_opts =
      [
        fitness_path: fitness,
        margin_mode: margin_mode(Keyword.get(opts, :margin_mode, "profile_floor"))
      ]
      |> maybe_put_multipliers(:high_multipliers, parse_multiplier_values(opts, :high_multiplier))
      |> maybe_put_multipliers(:low_multipliers, parse_multiplier_values(opts, :low_multiplier))

    with {:ok, read_result} <- FitnessDatasetReader.read(fitness),
         {:ok, report} <-
           ReflexCalibration.calibrate(
             Enum.map(read_result.records, & &1.record),
             calibration_opts
           ) do
      write_and_print_report(
        report,
        Keyword.get(opts, :out),
        Keyword.get(opts, :json, false),
        "TRINITY reflex calibration"
      )
    else
      {:error, reason} -> Mix.raise("trinity.reflex.calibrate failed: #{inspect(reason)}")
    end
  end

  def run(:trinity_sakana_candidate_eval, argv) do
    opts = CommandSpec.parse!(:trinity_sakana_candidate_eval, argv)
    _fitness = required!(opts, :fitness, "trinity.sakana.candidate_eval requires --fitness")

    if is_nil(Keyword.get(opts, :candidate_routes)) and
         is_nil(Keyword.get(opts, :candidate_vector)) do
      Mix.raise("trinity.sakana.candidate_eval requires --candidate-routes or --candidate-vector")
    end

    case CandidateEval.evaluate(opts) do
      {:ok, report} ->
        write_and_print_report(
          report,
          Keyword.get(opts, :out),
          Keyword.get(opts, :json, false),
          "TRINITY Sakana candidate eval"
        )

      {:error, reason} ->
        Mix.raise("trinity.sakana.candidate_eval failed: #{inspect(reason)}")
    end
  end

  def run(task_key, argv) do
    task_key
    |> CommandSpec.parse!(argv)
    |> then(&NativeTasks.run(task_key, &1))
  end

  defp required!(opts, key, message) do
    case Keyword.get(opts, key) do
      value when is_binary(value) and value != "" -> value
      _value -> Mix.raise(message)
    end
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

  defp write_and_print_report(report, out, json?, label) do
    bytes = Jason.encode!(report) <> "\n"

    if is_binary(out) do
      File.mkdir_p!(Path.dirname(out))
      File.write!(out, bytes)
    end

    if json? do
      IO.write(bytes)
    else
      Mix.shell().info(
        "#{label}: #{Map.get(report, :dataset_status) || Map.get(report, :status) || Map.get(report, :verdict) || "ok"}"
      )
    end

    :ok
  end

  defp content_mode("full"), do: :full
  defp content_mode("hash"), do: :hash
  defp content_mode(other), do: Mix.raise("unsupported fitness content mode: #{inspect(other)}")

  defp margin_mode("profile_floor"), do: :profile_floor
  defp margin_mode("absolute"), do: :absolute
  defp margin_mode(other), do: Mix.raise("unsupported fitness margin mode: #{inspect(other)}")

  defp parse_multiplier_values(opts, key) do
    values = Keyword.get_values(opts, key)

    if values == [] do
      nil
    else
      Enum.map(values, &parse_float!(&1, key))
    end
  end

  defp parse_float!(value, _key) when is_float(value), do: value
  defp parse_float!(value, _key) when is_integer(value), do: value * 1.0

  defp parse_float!(value, key) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} when number > 0 -> number
      _other -> Mix.raise("invalid #{key}: #{inspect(value)}")
    end
  end

  defp parse_float!(value, key), do: Mix.raise("invalid #{key}: #{inspect(value)}")

  defp maybe_put_multipliers(opts, _key, nil), do: opts
  defp maybe_put_multipliers(opts, key, values), do: Keyword.put(opts, key, values)
end
