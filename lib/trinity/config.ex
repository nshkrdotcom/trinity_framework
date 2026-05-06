defmodule Trinity.Config do
  @moduledoc """
  Compiled ref-only TRINITY runtime config.
  """

  alias Trinity.{ProviderPool, Registry, RouterArtifact}

  defstruct [:router_artifact, :registry, :provider_pool]

  @type t :: %__MODULE__{}

  def compile(attrs) when is_map(attrs) do
    with {:ok, router_artifact} <- RouterArtifact.new(fetch(attrs, :router_artifact, %{})),
         {:ok, registry} <- Registry.new(%{role_packs: fetch(attrs, :role_packs, [])}),
         {:ok, provider_pool} <- ProviderPool.new(fetch(attrs, :provider_pool, [])) do
      {:ok,
       %__MODULE__{
         router_artifact: router_artifact,
         registry: registry,
         provider_pool: provider_pool
       }}
    end
  end

  def compile(_attrs), do: {:error, :invalid_config}

  def compile!(attrs) do
    case compile(attrs) do
      {:ok, config} -> config
      {:error, reason} -> raise ArgumentError, "invalid TRINITY config: #{inspect(reason)}"
    end
  end

  defp fetch(attrs, key, default) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end
end
