defmodule TrinityFramework.Boundary.NoReflexDynamicAtomsTest do
  use ExUnit.Case, async: true

  @paths [
    "core/trinity_coordinator_core/lib/trinity/coordinator/reflex_policy.ex",
    "core/trinity_coordinator_core/lib/trinity/coordinator/orchestrator.ex",
    "core/trinity_coordinator_core/lib/trinity/coordinator/run_governance.ex",
    "tools/trinity_ops/lib/trinity/ops/orchestrator_runner.ex",
    "examples/qwen_router_prompt_eval/lib/qwen_router_prompt_eval.ex",
    "core/trinity_sakana_pipeline/lib/trinity/sakana/trace_fitness_assembler.ex"
  ]

  test "reflex input and CLI handling are dynamic-atom-free and regex-free" do
    forbidden = [
      "String." <> "to_atom",
      "String." <> "to_existing_atom",
      ":erlang." <> "binary_to_atom",
      "Reg" <> "ex.",
      "~" <> "r/"
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
