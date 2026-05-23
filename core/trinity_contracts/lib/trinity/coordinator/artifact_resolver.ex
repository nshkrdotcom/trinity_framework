defmodule Trinity.Coordinator.ArtifactResolver do
  @moduledoc """
  Behaviour for resolving opaque artifact references.
  """

  alias Trinity.Coordinator.ArtifactRef

  @callback resolve(ArtifactRef.t(), keyword()) :: {:ok, ArtifactRef.t()} | {:error, term()}
end
