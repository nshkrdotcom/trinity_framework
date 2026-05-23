defmodule Trinity.SingleNode.Config do
  @moduledoc """
  Runtime configuration boundary for the standalone TRINITY single-node app.
  """

  @default_artifact_root Path.expand(
                           "../../../../../../trinity_coordinator/priv/sakana_trinity/adapted_qwen3_0_6b_layer26",
                           __DIR__
                         )

  @runtime_profiles [:cuda_exla, :host_exla, :binary, :mock_tiny, :emlx, :emily, :custom]

  @spec runtime_profile() :: atom()
  def runtime_profile do
    :trinity_single_node
    |> Application.get_env(:runtime_profile, :cuda_exla)
    |> normalize_runtime_profile!()
  end

  @spec artifact_root() :: String.t()
  def artifact_root do
    Application.get_env(:trinity_single_node, :artifact_root, @default_artifact_root)
  end

  @spec providers_enabled?() :: boolean()
  def providers_enabled? do
    :trinity_single_node
    |> Application.get_env(:providers_enabled?, false)
    |> truthy?()
  end

  @spec provider_pool() :: atom() | String.t() | list()
  def provider_pool do
    Application.get_env(:trinity_single_node, :provider_pool, :mock)
  end

  @spec provider_opts() :: keyword()
  def provider_opts do
    :trinity_single_node
    |> Application.get_env(:provider_opts, [])
    |> normalize_keyword()
    |> Keyword.put(:provider_pool, provider_pool())
    |> Keyword.put(:providers_enabled?, providers_enabled?())
  end

  @spec hf_hub_token() :: String.t() | nil
  def hf_hub_token, do: Application.get_env(:hf_hub, :token)

  @spec hf_hub_config() :: map()
  def hf_hub_config, do: :hf_hub |> Application.get_all_env() |> Map.new()

  @spec normalize_runtime_profile!(atom() | String.t()) :: atom()
  def normalize_runtime_profile!(profile) when is_atom(profile) and profile in @runtime_profiles,
    do: profile

  def normalize_runtime_profile!(profile) when is_binary(profile) do
    normalized =
      profile
      |> String.trim()
      |> String.downcase()

    Enum.find(@runtime_profiles, fn candidate -> Atom.to_string(candidate) == normalized end) ||
      raise ArgumentError, "invalid runtime profile: #{inspect(profile)}"
  end

  def normalize_runtime_profile!(profile) do
    raise ArgumentError, "invalid runtime profile: #{inspect(profile)}"
  end

  defp truthy?(value) when value in [true, 1, "1", "true", "TRUE", "yes", "YES"], do: true
  defp truthy?(_value), do: false

  defp normalize_keyword(value) when is_list(value), do: value
  defp normalize_keyword(value) when is_map(value), do: Map.to_list(value)
  defp normalize_keyword(_value), do: []
end
