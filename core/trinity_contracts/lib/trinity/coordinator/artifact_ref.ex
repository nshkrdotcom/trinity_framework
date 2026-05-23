defmodule Trinity.Coordinator.ArtifactRef do
  @moduledoc """
  Opaque artifact identity carried between runtime and coordinator packages.
  """

  @enforce_keys [:artifact_ref]
  defstruct [
    :artifact_ref,
    :kind,
    :uri,
    :sha256,
    :manifest_ref,
    :pin_ref,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          artifact_ref: String.t(),
          kind: atom() | nil,
          uri: String.t() | nil,
          sha256: String.t() | nil,
          manifest_ref: String.t() | nil,
          pin_ref: String.t() | nil,
          metadata: map()
        }
end
