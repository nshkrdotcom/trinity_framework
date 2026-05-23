defmodule Trinity.Coordinator.RoleInjector do
  @moduledoc """
  Injects TRINITY role prompts and normalizes role names.
  """

  @role_names %{0 => "Worker", 1 => "Thinker", 2 => "Verifier"}

  @role_aliases %{
    "0" => "Worker",
    "1" => "Thinker",
    "2" => "Verifier",
    "solver" => "Worker",
    "t" => "Thinker",
    "thinker" => "Thinker",
    "v" => "Verifier",
    "verifier" => "Verifier",
    "w" => "Worker",
    "worker" => "Worker"
  }

  @roles %{
    "Thinker" =>
      "Analyze the current state and provide high-level guidance, plans, decompositions, or critiques. Do not present unchecked final answers unless the transcript already contains enough evidence.",
    "Worker" =>
      "Execute the next concrete step of the plan. Write code, math, derivations, calculations, or concrete answer content that advances the solution.",
    "Verifier" =>
      "Check the current solution for correctness, completeness, and responsiveness. Start your response with exactly ACCEPT or REVISE. After REVISE, include a concise diagnosis."
  }

  @spec inject_role([map()], term()) :: [map()]
  def inject_role(messages, role) when is_list(messages) do
    role = role_name(role)
    system_prompt = Map.get(@roles, role, "You are a helpful assistant.")
    [%{role: "system", content: system_prompt}] ++ messages
  end

  @spec role_name(term()) :: String.t()
  def role_name(role_id) when is_integer(role_id),
    do: Map.get(@role_names, role_id, "UnknownRole")

  def role_name(role) when is_atom(role) do
    role
    |> Atom.to_string()
    |> role_name()
  end

  def role_name(role) when is_binary(role) do
    normalized = role |> String.trim() |> String.downcase()
    Map.get(@role_aliases, normalized, role)
  end

  def role_name(_), do: "UnknownRole"

  @spec role_atom(term()) :: :worker | :thinker | :verifier | :unknown
  def role_atom(role) do
    case role_name(role) do
      "Thinker" -> :thinker
      "Worker" -> :worker
      "Verifier" -> :verifier
      _ -> :unknown
    end
  end

  @spec role_id(term()) :: 0 | 1 | 2 | nil
  def role_id(role) do
    case role_name(role) do
      "Worker" -> 0
      "Thinker" -> 1
      "Verifier" -> 2
      _ -> nil
    end
  end
end
