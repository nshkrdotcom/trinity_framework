defmodule Trinity.Coordinator.HiddenStateExtractionPlan do
  @moduledoc """
  Plan handed to a model runtime for the internal extract+route operation.
  """

  alias Trinity.Coordinator.{AdapterRef, ArtifactRef, RuntimeProfileRef}

  @enforce_keys [:adapter_ref, :messages]
  defstruct [
    :adapter_ref,
    :artifact_ref,
    :runtime_profile_ref,
    messages: [],
    options: %{},
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          adapter_ref: AdapterRef.t(),
          artifact_ref: ArtifactRef.t() | nil,
          runtime_profile_ref: RuntimeProfileRef.t() | nil,
          messages: [map()],
          options: map(),
          metadata: map()
        }
end
