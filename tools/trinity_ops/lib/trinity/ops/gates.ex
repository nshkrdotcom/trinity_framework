defmodule Trinity.Ops.Gates do
  @moduledoc """
  Framework-native implementation of `mix trinity.gates`.
  """

  alias Trinity.Ops.CommandSpec

  @summary_schema_version 1

  @baseline_steps [
    {:format, ["format", "--check-formatted"]},
    {:compile, ["compile", "--warnings-as-errors"]},
    {:test, ["test"]},
    {:credo, ["credo", "--strict"]},
    {:dialyzer, ["dialyzer", "--format", "short"]},
    {:docs, ["docs", "--warnings-as-errors"]}
  ]

  @spec run([String.t()]) :: :ok
  def run(argv) do
    opts = CommandSpec.parse!(:trinity_gates, argv)
    fast? = Keyword.get(opts, :fast, false)

    steps =
      @baseline_steps
      |> maybe_drop(:dialyzer, fast? or Keyword.get(opts, :skip_dialyzer, false))
      |> maybe_drop(:docs, fast? or Keyword.get(opts, :skip_docs, false))
      |> Kernel.++(optional_steps(opts))

    started = System.monotonic_time(:millisecond)
    results = Enum.map(steps, &run_step/1)
    duration_ms = System.monotonic_time(:millisecond) - started
    ok? = Enum.all?(results, &(&1.exit_status == 0))

    maybe_write_summary(opts, %{
      schema_version: @summary_schema_version,
      ok: ok?,
      duration_ms: duration_ms,
      steps: results
    })

    if ok?, do: :ok, else: Mix.raise("trinity.gates failed")
  end

  defp maybe_drop(steps, _name, false), do: steps
  defp maybe_drop(steps, name, true), do: Enum.reject(steps, fn {step, _args} -> step == name end)

  defp optional_steps(opts) do
    []
    |> maybe_include(
      Keyword.get(opts, :include_parity_check, false),
      {:parity_check, parity_args(opts)}
    )
    |> maybe_include(Keyword.get(opts, :include_hex_build, false), {:hex_build, ["hex.build"]})
  end

  defp maybe_include(steps, false, _step), do: steps
  defp maybe_include(steps, true, step), do: steps ++ [step]

  defp parity_args(opts) do
    ["trinity.parity.check"]
    |> maybe_append("--python-report", Keyword.get(opts, :python_report))
    |> maybe_append("--elixir-report", Keyword.get(opts, :elixir_report))
  end

  defp maybe_append(args, _flag, nil), do: args
  defp maybe_append(args, flag, value), do: args ++ [flag, value]

  defp run_step({step, args}) do
    Mix.shell().info("")
    Mix.shell().info("[trinity.gates] step=#{step} cmd=mix args=#{inspect(args)}")

    started = System.monotonic_time(:millisecond)

    {_output, exit_status} =
      System.cmd("mix", args, into: IO.stream(:stdio, :line), stderr_to_stdout: true)

    duration_ms = System.monotonic_time(:millisecond) - started

    Mix.shell().info(
      "[trinity.gates] step=#{step} exit=#{exit_status} duration_ms=#{duration_ms}"
    )

    %{
      step: step,
      command: "mix",
      args: args,
      exit_status: exit_status,
      duration_ms: duration_ms
    }
  end

  defp maybe_write_summary(opts, summary) do
    case Keyword.get(opts, :summary_out) do
      nil ->
        :ok

      path ->
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, Jason.encode!(summary, pretty: true))
        Mix.shell().info("[trinity.gates] summary written: #{path}")
    end
  end
end
