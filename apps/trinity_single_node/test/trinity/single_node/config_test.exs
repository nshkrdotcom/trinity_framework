defmodule Trinity.SingleNode.ConfigTest do
  use ExUnit.Case, async: false

  alias Trinity.SingleNode.Config

  setup do
    previous = %{
      runtime_profile: Application.get_env(:trinity_single_node, :runtime_profile),
      providers_enabled?: Application.get_env(:trinity_single_node, :providers_enabled?),
      provider_opts: Application.get_env(:trinity_single_node, :provider_opts),
      provider_pool: Application.get_env(:trinity_single_node, :provider_pool)
    }

    on_exit(fn ->
      restore_env(:runtime_profile, previous.runtime_profile)
      restore_env(:providers_enabled?, previous.providers_enabled?)
      restore_env(:provider_opts, previous.provider_opts)
      restore_env(:provider_pool, previous.provider_pool)
    end)

    :ok
  end

  test "runtime profile defaults to cuda_exla and can be overridden through app config" do
    Application.delete_env(:trinity_single_node, :runtime_profile)
    assert Config.runtime_profile() == :cuda_exla

    Application.put_env(:trinity_single_node, :runtime_profile, "mock_tiny")
    assert Config.runtime_profile() == :mock_tiny
  end

  test "provider options fail closed unless explicitly enabled" do
    Application.put_env(:trinity_single_node, :providers_enabled?, false)
    Application.put_env(:trinity_single_node, :provider_pool, :mock)
    Application.put_env(:trinity_single_node, :provider_opts, api_key: "secret")

    opts = Config.provider_opts()

    assert opts[:provider_pool] == :mock
    assert opts[:providers_enabled?] == false
    assert opts[:api_key] == "secret"
  end

  test "runtime.exs materializes only the four HF env vars" do
    config =
      read_runtime_config(%{
        "HF_TOKEN" => "hf-token",
        "HF_HUB_CACHE" => "/tmp/hf-cache",
        "HF_HOME" => "/tmp/hf-home",
        "HF_HUB_OFFLINE" => "true",
        "TRINITY_RUNTIME_PROFILE" => "mock_tiny"
      })

    assert config_value(config, :hf_hub, :token) == "hf-token"
    assert config_value(config, :hf_hub, :cache_dir) == "/tmp/hf-cache"
    assert config_value(config, :hf_hub, :offline) == true
    refute Keyword.has_key?(config, :trinity_single_node)
  end

  test "HF_HOME maps to hub cache when HF_HUB_CACHE is absent" do
    config = read_runtime_config(%{"HF_HOME" => "/tmp/hf-home"})
    assert config_value(config, :hf_hub, :cache_dir) == "/tmp/hf-home/hub"
  end

  defp read_runtime_config(env_values) do
    env =
      Enum.map(runtime_env_keys(), fn key ->
        {key, Map.get(env_values, key)}
      end)

    {out, 0} =
      System.cmd("elixir", ["-e", runtime_config_script()],
        env: env,
        stderr_to_stdout: true
      )

    out
    |> Base.decode64!()
    |> :erlang.binary_to_term()
  end

  defp config_value(config, app, key) do
    config
    |> Keyword.get_values(app)
    |> Enum.reduce([], &Keyword.merge(&2, &1))
    |> Keyword.get(key)
  end

  defp runtime_env_keys do
    ["HF_TOKEN", "HF_HUB_CACHE", "HF_HOME", "HF_HUB_OFFLINE", "TRINITY_RUNTIME_PROFILE"]
  end

  defp runtime_config_script do
    runtime_path = Path.expand("../../../config/runtime.exs", __DIR__)

    """
    config = Config.Reader.read!(#{inspect(runtime_path)})
    IO.write(Base.encode64(:erlang.term_to_binary(config)))
    """
  end

  defp restore_env(key, nil), do: Application.delete_env(:trinity_single_node, key)
  defp restore_env(key, value), do: Application.put_env(:trinity_single_node, key, value)
end
