defmodule TrinityFramework.Integration.CrucibleProviderRoutingAuditTest do
  use ExUnit.Case, async: true

  @routing_sources [
    "core/trinity_coordinator_core/lib/trinity/crucible",
    "tools/trinity_ops/lib/trinity/ops/native_tasks.ex"
  ]

  test "Crucible routing code records provider kind without branching on provider identity" do
    offenders =
      @routing_sources
      |> Enum.flat_map(&source_files/1)
      |> Enum.flat_map(&provider_identity_branch_lines/1)

    assert offenders == []
  end

  defp source_files(path) do
    cond do
      File.dir?(path) -> path |> Path.join("**/*.ex") |> Path.wildcard()
      File.regular?(path) -> [path]
      true -> []
    end
  end

  defp provider_identity_branch_lines(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _line_number} ->
      String.contains?(line, "provider_kind") and branch_operator?(line)
    end)
    |> Enum.map(fn {line, line_number} -> "#{path}:#{line_number}:#{String.trim(line)}" end)
  end

  defp branch_operator?(line) do
    String.contains?(line, ["==", "!=", " in ", "case ", "cond do", "if "])
  end
end
