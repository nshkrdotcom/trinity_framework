defmodule Trinity.Bridge.SelfHostedInference.Boundary.NoLibOsEnvTest do
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
    |> Enum.filter(&(String.ends_with?(&1, ".ex") or String.ends_with?(&1, ".exs")))
    |> Enum.flat_map(&file_hits/1)
  end

  defp file_hits(path) do
    body = File.read!(path)

    Enum.flat_map(@forbidden, &token_hits(path, body, &1))
  end

  defp token_hits(path, body, token) do
    if String.contains?(body, token), do: [{path, token}], else: []
  end
end
