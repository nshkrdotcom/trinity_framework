defmodule Trinity.Ops.Forwarder do
  @moduledoc """
  Transitional command forwarder for coordinator-owned operator tasks.

  `0119_master_buildout_checklist.md` permits new-to-old task shims through
  Phases 10-15 while the final task bodies are audited against the monolith.
  """

  alias Trinity.Ops.CommandSpec

  @spec forward!(CommandSpec.task_key(), [String.t()]) :: :ok
  def forward!(task_key, argv) do
    task_name = CommandSpec.task_name!(task_key)
    coordinator_dir = coordinator_dir!()

    Mix.shell().info("[trinity_ops] forwarding #{task_name} to #{coordinator_dir}")

    {_output, status} =
      System.cmd("mix", [task_name | argv],
        cd: coordinator_dir,
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    if status == 0, do: :ok, else: Mix.raise("#{task_name} failed with exit status #{status}")
  end

  defp coordinator_dir! do
    candidates = [
      Path.expand("../../../../../../trinity_coordinator", __DIR__),
      "/home/home/p/g/n/trinity_coordinator"
    ]

    case Enum.find(candidates, &File.dir?/1) do
      nil -> Mix.raise("cannot locate sibling trinity_coordinator checkout")
      path -> path
    end
  end
end
