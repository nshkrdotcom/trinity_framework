defmodule TrinityFramework.Boundary.NoFitnessExportDynamicAtomsTest do
  use ExUnit.Case, async: true

  @paths [
    "core/trinity_sakana_contracts/lib/trinity/sakana/fitness_example.ex",
    "core/trinity_sakana_contracts/lib/trinity/sakana/fitness_manifest.ex",
    "core/trinity_sakana_contracts/lib/trinity/sakana/fitness_score.ex",
    "core/trinity_sakana_pipeline/lib/trinity/sakana/trace_fitness_reader.ex",
    "core/trinity_sakana_pipeline/lib/trinity/sakana/trace_fitness_assembler.ex",
    "core/trinity_sakana_pipeline/lib/trinity/sakana/fitness_jsonl_writer.ex",
    "core/trinity_sakana_pipeline/lib/trinity/sakana/fitness_exporter.ex"
  ]

  test "fitness input handling is dynamic-atom-free and regex-free" do
    forbidden = [
      "String.to_atom",
      "String.to_existing_atom",
      ":erlang.binary_to_atom",
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
