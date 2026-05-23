defmodule Trinity.Ops.Tasks do
  @moduledoc """
  Dispatch layer for the `mix trinity.*` task modules.
  """

  alias Trinity.Ops.{CommandSpec, Gates}

  @forwarded_tasks [
    :trinity_artifact_fetch,
    :trinity_demo,
    :trinity_hitl_adapted,
    :trinity_hitl_base_qwen,
    :trinity_hitl_gpu,
    :trinity_hitl_head_route,
    :trinity_hitl_mock_loop,
    :trinity_hitl_vector,
    :trinity_parity_check,
    :trinity_route_demo,
    :trinity_sakana_export_adapted,
    :trinity_sakana_import_python,
    :trinity_sakana_large_tensor_chunks,
    :trinity_sakana_parity_sample,
    :trinity_sakana_router_trace
  ]

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

  def run(task_key, argv) when task_key in @forwarded_tasks do
    _opts = CommandSpec.parse!(task_key, argv)
    unsupported_task!(task_key)
  end

  defp unsupported_task!(task_key) do
    if Application.get_env(:trinity_ops, :allow_unported_task_success, false) do
      Mix.shell().error("#{CommandSpec.task_name!(task_key)} is not yet framework-native")
      :ok
    else
      Mix.raise("""
      #{CommandSpec.task_name!(task_key)} is no longer forwarded to trinity_coordinator.

      Phase 16 retired trinity_coordinator as the command owner. Use the framework
      package APIs directly while the remaining heavy operator task bodies are
      completed in tools/trinity_ops.
      """)
    end
  end

  defp check_requirement!("cuda") do
    {target, 0} = System.cmd("sh", ["-c", "printf %s \"${XLA_TARGET:-}\""])

    unless target == "cuda12" do
      Mix.raise("XLA_TARGET=cuda12 is required for CUDA runtime checks")
    end
  end

  defp check_requirement!("artifact"), do: :ok
  defp check_requirement!(other), do: Mix.raise("unknown environment requirement: #{other}")
end
