defmodule Trinity.Contracts.Boundary.NoStringToAtomTest do
  use ExUnit.Case, async: true

  @forbidden ~w(String.to_atom String.to_existing_atom)

  test "core code avoids dynamic atom creation" do
    assert forbidden_hits() == []
  end

  defp forbidden_hits do
    {out, 0} = System.cmd("git", ["ls-files", "lib/"])

    out
    |> String.split("\n", trim: true)
    |> Enum.filter(&(String.ends_with?(&1, ".ex") or String.ends_with?(&1, ".exs")))
    |> Enum.flat_map(fn path ->
      body = File.read!(path)

      Enum.flat_map(@forbidden, fn token ->
        if String.contains?(body, token), do: [{path, token}], else: []
      end)
    end)
  end
end
