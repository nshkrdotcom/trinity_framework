defmodule Trinity.CoordinatorCore.Boundary.NoLibOsEnvTest do
  use ExUnit.Case, async: true

  @forbidden ~w(
    System.get_env
    System.fetch_env
    System.fetch_env!
    System.put_env
    System.delete_env
  )

  test "no lib/** Elixir source calls direct OS env APIs" do
    assert forbidden_hits() == []
  end

  defp forbidden_hits do
    {out, 0} = System.cmd("git", ["ls-files", "lib/"])

    out
    |> String.split("\n", trim: true)
    |> Enum.filter(&(File.regular?(&1) and elixir_source?(&1)))
    |> Enum.flat_map(&forbidden_hits_in_file/1)
  end

  defp elixir_source?(path), do: String.ends_with?(path, ".ex") or String.ends_with?(path, ".exs")

  defp forbidden_hits_in_file(path) do
    body = File.read!(path)

    @forbidden
    |> Enum.filter(&String.contains?(body, &1))
    |> Enum.map(&{path, &1})
  end
end
