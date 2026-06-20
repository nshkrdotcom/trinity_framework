defmodule TrinityFramework.Boundary.NoAdaptationReadinessDynamicAtomsTest do
  use ExUnit.Case, async: true

  @paths [
    "core/trinity_sakana_contracts/lib/trinity/sakana/fitness_dataset_report.ex",
    "core/trinity_sakana_contracts/lib/trinity/sakana/fitness_replay_report.ex",
    "core/trinity_sakana_contracts/lib/trinity/sakana/reflex_calibration_report.ex",
    "core/trinity_sakana_contracts/lib/trinity/sakana/adaptation_proposal.ex",
    "core/trinity_sakana_pipeline/lib/trinity/sakana/fitness_dataset_reader.ex",
    "core/trinity_sakana_pipeline/lib/trinity/sakana/fitness_dataset_inspector.ex",
    "core/trinity_sakana_pipeline/lib/trinity/sakana/fitness_replay.ex",
    "core/trinity_sakana_pipeline/lib/trinity/sakana/candidate_eval.ex",
    "core/trinity_coordinator_core/lib/trinity/coordinator/reflex_calibration.ex",
    "tools/trinity_ops/lib/mix/tasks/trinity.sakana.fitness_inspect.ex",
    "tools/trinity_ops/lib/mix/tasks/trinity.sakana.fitness_replay.ex",
    "tools/trinity_ops/lib/mix/tasks/trinity.reflex.calibrate.ex",
    "tools/trinity_ops/lib/mix/tasks/trinity.sakana.candidate_eval.ex"
  ]

  test "adaptation readiness code is dynamic-atom-free and regex-free" do
    forbidden = [
      "String.to_atom",
      "String.to_existing_atom",
      ":erlang.binary_to_atom",
      "Reg" <> "ex.",
      "~" <> "r/"
    ]

    assert offenders(forbidden) == []
  end

  defp offenders(terms) do
    for path <- @paths,
        source = path |> projected_path() |> File.read!(),
        term <- terms,
        String.contains?(source, term),
        do: {path, term}
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
