defmodule Trinity.RouterHead do
  @moduledoc """
  Deterministic role selection contract for the framework boundary.
  """

  alias Trinity.Registry

  def select_role(%Registry{} = registry, preferred_role_ref) do
    role_packs = Registry.role_packs(registry)

    cond do
      role_packs == [] ->
        {:error, :no_role_packs}

      is_binary(preferred_role_ref) ->
        select_preferred(role_packs, preferred_role_ref)

      true ->
        {:ok, List.first(role_packs), :default_route}
    end
  end

  defp select_preferred(role_packs, preferred_role_ref) do
    case Enum.find(role_packs, &(&1.role_ref == preferred_role_ref)) do
      nil -> {:ok, List.first(role_packs), :invalid_route}
      role_pack -> {:ok, role_pack, :selected}
    end
  end
end
