defmodule Trinity.Coordinator.RuntimeProfileRef do
  @moduledoc """
  Dependency-free runtime profile reference.
  """

  @enforce_keys [:name]
  defstruct [
    :name,
    kind: :route_logits,
    require_cuda?: false,
    qwen_runtime?: false,
    artifact_runtime?: false,
    capabilities: %{},
    margin_defaults: %{},
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          kind: :route_logits | :crucible | atom(),
          require_cuda?: boolean(),
          qwen_runtime?: boolean(),
          artifact_runtime?: boolean(),
          capabilities: map(),
          margin_defaults: map(),
          metadata: map()
        }
end
