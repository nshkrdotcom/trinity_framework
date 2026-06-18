defmodule Trinity.SingleNode.LoadedRuntime do
  @moduledoc """
  Runtime handle carrying the identity that was executed.

  The lower self-hosted runtime adapter is intentionally wrapped so routing and
  traces use the identity resolved at load time instead of relabeling the
  runtime from later call options.
  """

  alias Trinity.Bridge.SelfHostedInference.RuntimeAdapter
  alias Trinity.SingleNode.ArtifactIdentity

  @enforce_keys [:runtime, :runtime_profile, :artifact_identity, :backend_identity]
  defstruct [:runtime, :runtime_profile, :artifact_identity, :backend_identity]

  @type t :: %__MODULE__{
          runtime: RuntimeAdapter.t(),
          runtime_profile: atom(),
          artifact_identity: map(),
          backend_identity: map()
        }

  @spec new(RuntimeAdapter.t(), atom(), map(), map()) :: t()
  def new(%RuntimeAdapter{} = runtime, runtime_profile, artifact_identity, backend_identity)
      when is_atom(runtime_profile) and is_map(artifact_identity) and is_map(backend_identity) do
    %__MODULE__{
      runtime: runtime,
      runtime_profile: runtime_profile,
      artifact_identity: ArtifactIdentity.mark_loaded(artifact_identity),
      backend_identity: backend_identity
    }
  end
end
