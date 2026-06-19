defmodule TrinityFramework.Boundary.NoReflexForbiddenEnvTest do
  use ExUnit.Case, async: true

  @paths [
    "core/trinity_coordinator_core/lib/trinity/coordinator/reflex_policy.ex",
    "core/trinity_coordinator_core/lib/trinity/coordinator/orchestrator.ex",
    "core/trinity_coordinator_core/lib/trinity/coordinator/run_governance.ex",
    "tools/trinity_ops/lib/trinity/ops/orchestrator_runner.ex",
    "examples/qwen_router_prompt_eval/lib/qwen_router_prompt_eval.ex"
  ]

  test "reflex runtime, task, and eval code has no direct OS environment access" do
    forbidden = [
      "System." <> "get_env",
      "System." <> "fetch_env",
      "System." <> "put_env",
      "System." <> "delete_env"
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
