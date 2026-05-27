import Config

config :trinity_ops,
  crucible_live_enabled?: System.get_env("TRINITY_CRUCIBLE_LIVE") in ["1", "true"]
