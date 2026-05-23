import Config

if token = System.get_env("HF_TOKEN") do
  config :hf_hub, token: token
end

cond do
  dir = System.get_env("HF_HUB_CACHE") ->
    config :hf_hub, cache_dir: dir

  dir = System.get_env("HF_HOME") ->
    config :hf_hub, cache_dir: Path.join(dir, "hub")

  true ->
    :ok
end

if System.get_env("HF_HUB_OFFLINE") in ~w(1 true) do
  config :hf_hub, offline: true
end
