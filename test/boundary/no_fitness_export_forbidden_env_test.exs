defmodule TrinityFramework.Boundary.NoFitnessExportForbiddenEnvTest do
  use ExUnit.Case, async: true

  @paths [
    "tools/trinity_ops/lib/trinity/ops/orchestrator_runner.ex",
    "tools/trinity_ops/lib/mix/tasks/trinity.orchestrator.demo.ex",
    "tools/trinity_ops/lib/mix/tasks/trinity.sakana.fitness_export.ex",
    "core/trinity_sakana_pipeline/lib/trinity/sakana/fitness_exporter.ex"
  ]

  test "fitness runtime and task code has no direct OS environment access" do
    forbidden = [
      "System.get_env",
      "System.fetch_env",
      "System.put_env",
      "System.delete_env"
    ]

    offenders =
      for path <- @paths,
          source = path |> projected_path() |> File.read!(),
          term <- forbidden,
          String.contains?(source, term),
          do: {path, term}

    assert offenders == []
  end

  defp projected_path(path) do
    [_component_path, lib_path] = String.split(path, "/lib/", parts: 2)

    [path, Path.join("components", path), Path.join("lib", lib_path)]
    |> Enum.find(&File.regular?/1)
    |> case do
      nil -> raise File.Error, reason: :enoent, action: "locate source", path: path
      resolved -> resolved
    end
  end
end
