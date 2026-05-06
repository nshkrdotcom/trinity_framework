defmodule Trinity.Registry do
  @moduledoc """
  In-memory registry for ref-only TRINITY role packs.
  """

  alias Trinity.RolePack

  defstruct role_packs: %{}

  @type t :: %__MODULE__{role_packs: %{String.t() => RolePack.t()}}

  def new(attrs) when is_map(attrs) do
    attrs
    |> Map.get(:role_packs, Map.get(attrs, "role_packs", []))
    |> normalize_role_packs()
  end

  def fetch_role_pack(%__MODULE__{role_packs: role_packs}, role_ref) when is_binary(role_ref) do
    case Map.fetch(role_packs, role_ref) do
      {:ok, role_pack} -> {:ok, role_pack}
      :error -> {:error, {:unknown_role_pack, role_ref}}
    end
  end

  def role_packs(%__MODULE__{role_packs: role_packs}) do
    role_packs
    |> Map.values()
    |> Enum.sort_by(& &1.role_ref)
  end

  defp normalize_role_packs(role_packs) when is_list(role_packs) do
    role_packs
    |> Enum.reduce_while(%{}, fn attrs, acc ->
      case RolePack.new(attrs) do
        {:ok, role_pack} -> {:cont, Map.put(acc, role_pack.role_ref, role_pack)}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      packs -> {:ok, %__MODULE__{role_packs: packs}}
    end
  end

  defp normalize_role_packs(_role_packs), do: {:error, :invalid_role_packs}
end
