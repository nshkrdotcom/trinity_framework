defmodule Trinity.Coordinator.RuntimeProfileRef do
  @moduledoc """
  Dependency-free runtime profile reference.
  """

  @enforce_keys [:name]
  defstruct [
    :name,
    require_cuda?: false,
    qwen_runtime?: false,
    artifact_runtime?: false,
    capabilities: %{},
    margin_defaults: %{},
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          require_cuda?: boolean(),
          qwen_runtime?: boolean(),
          artifact_runtime?: boolean(),
          capabilities: map(),
          margin_defaults: map(),
          metadata: map()
        }
end
