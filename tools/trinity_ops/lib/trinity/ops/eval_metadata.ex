defmodule Trinity.Ops.EvalMetadata do
  @moduledoc """
  Metadata helpers for operator eval reports.

  Eval output must distinguish a mock contract-path pass from a run that
  actually identified the Qwen/Sakana route artifact.
  """

  alias Trinity.SingleNode.ArtifactIdentity

  @spec matrix(atom(), String.t() | nil, keyword()) :: map()
  def matrix(runtime_profile, artifact_root, opts \\ []) do
    identity = ArtifactIdentity.resolve(runtime_profile, artifact_root, opts)

    %{
      runtime_profile: Atom.to_string(runtime_profile),
      eval_mode: eval_mode(runtime_profile, identity),
      qwen_loaded?: identity.qwen_loaded?,
      acceptance_level: acceptance_level(runtime_profile, identity),
      snapshot_policy: snapshot_policy(identity),
      model_id: identity.model_id,
      adapter_id: identity.adapter_id,
      artifact_ref: identity.artifact_ref,
      artifact_status: identity.artifact_status
    }
  end

  defp eval_mode(:mock_tiny, _identity), do: "mock_tiny contract eval"
  defp eval_mode(:cuda_exla, %{qwen_loaded?: true}), do: "CUDA Qwen route eval"
  defp eval_mode(_runtime_profile, %{qwen_loaded?: true}), do: "Qwen route runtime eval"

  defp eval_mode(_runtime_profile, _identity),
    do: "route runtime eval without Qwen artifact identity"

  defp acceptance_level(:mock_tiny, _identity), do: "Contract-path eval only; does not load Qwen"

  defp acceptance_level(_runtime_profile, %{qwen_loaded?: true}),
    do: "Route, margin, determinism, and Crucible contract acceptance"

  defp acceptance_level(_runtime_profile, _identity),
    do: "Contract/runtime path acceptance; Qwen artifact identity is unavailable"

  defp snapshot_policy(%{qwen_loaded?: true}),
    do: "Strict Qwen snapshot acceptance belongs to the direct example eval fixture"

  defp snapshot_policy(_identity), do: "No Qwen logits snapshot is used without Qwen identity"
end
