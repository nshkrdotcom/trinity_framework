defmodule Trinity.SingleNode.ConfigTest do
  use ExUnit.Case, async: false

  alias Elixir.Config.Reader, as: ConfigReader
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
    with_env(
      %{
        "HF_TOKEN" => "hf-token",
        "HF_HUB_CACHE" => "/tmp/hf-cache",
        "HF_HOME" => "/tmp/hf-home",
        "HF_HUB_OFFLINE" => "true",
        "TRINITY_RUNTIME_PROFILE" => "mock_tiny"
      },
      fn ->
        config = read_runtime_config()

        assert config_value(config, :hf_hub, :token) == "hf-token"
        assert config_value(config, :hf_hub, :cache_dir) == "/tmp/hf-cache"
        assert config_value(config, :hf_hub, :offline) == true
        refute Keyword.has_key?(config, :trinity_single_node)
      end
    )
  end

  test "HF_HOME maps to hub cache when HF_HUB_CACHE is absent" do
    with_env(%{"HF_HOME" => "/tmp/hf-home"}, fn ->
      config = read_runtime_config()
      assert config_value(config, :hf_hub, :cache_dir) == "/tmp/hf-home/hub"
    end)
  end

  defp read_runtime_config do
    ConfigReader.read!(Path.expand("../../../config/runtime.exs", __DIR__))
  end

  defp config_value(config, app, key) do
    config
    |> Keyword.get_values(app)
    |> Enum.reduce([], &Keyword.merge(&2, &1))
    |> Keyword.get(key)
  end

  defp with_env(values, fun) do
    keys = ["HF_TOKEN", "HF_HUB_CACHE", "HF_HOME", "HF_HUB_OFFLINE", "TRINITY_RUNTIME_PROFILE"]
    previous = Map.new(keys, &{&1, System.get_env(&1)})

    try do
      Enum.each(keys, &System.delete_env/1)
      Enum.each(values, fn {key, value} -> System.put_env(key, value) end)
      fun.()
    after
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:trinity_single_node, key)
  defp restore_env(key, value), do: Application.put_env(:trinity_single_node, key, value)
end
