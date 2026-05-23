import Config

config :trinity_single_node,
  runtime_profile: :cuda_exla,
  providers_enabled?: false,
  provider_pool: :mock

env_config = Path.expand("#{config_env()}.exs", __DIR__)

if File.exists?(env_config) do
  import_config "#{config_env()}.exs"
end
