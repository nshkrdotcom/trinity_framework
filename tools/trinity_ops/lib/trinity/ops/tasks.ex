defmodule Trinity.Ops.Tasks do
  @moduledoc """
  Dispatch layer for the `mix trinity.*` task modules.
  """

  alias SelfHostedInferenceBumblebee.Runtime.Preflight
  alias Trinity.Ops.{CommandSpec, Gates, NativeTasks}

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
end
