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
    qwen_route_ready? = ArtifactIdentity.qwen_route_ready?(identity)

    %{
      runtime_profile: Atom.to_string(runtime_profile),
      eval_mode: eval_mode(runtime_profile, identity, qwen_route_ready?),
      qwen_loaded?: identity.qwen_loaded?,
      qwen_base_model?: identity.qwen_base_model?,
      sakana_route_artifact?: identity.sakana_route_artifact?,
      qwen_route_ready?: qwen_route_ready?,
      artifact_available?: identity.artifact_available?,
      artifact_pin_verified?: identity.artifact_pin_verified?,
      acceptance_level: acceptance_level(runtime_profile, identity, qwen_route_ready?),
      snapshot_policy: snapshot_policy(qwen_route_ready?),
      model_id: identity.model_id,
      adapter_id: identity.adapter_id,
      artifact_ref: identity.artifact_ref,
      artifact_status: identity.artifact_status,
      artifact_status_reason: identity.artifact_status_reason,
      artifact_manifest_sha256_actual: identity.artifact_manifest_sha256_actual,
      artifact_pin_manifest_sha256: identity.artifact_pin_manifest_sha256
    }
  end

  defp eval_mode(:mock_tiny, _identity, _qwen_route_ready?), do: "mock_tiny contract eval"
  defp eval_mode(:cuda_exla, _identity, true), do: "CUDA Qwen/Sakana route eval"
  defp eval_mode(_runtime_profile, _identity, true), do: "Qwen/Sakana route runtime eval"

  defp eval_mode(_runtime_profile, _identity, false),
    do: "route runtime eval without Qwen artifact identity"

  defp acceptance_level(:mock_tiny, _identity, _qwen_route_ready?),
    do: "Contract-path eval only; does not load Qwen"

  defp acceptance_level(_runtime_profile, _identity, true),
    do: "Route, margin, determinism, and Crucible contract acceptance"

  defp acceptance_level(_runtime_profile, _identity, false),
    do: "Contract/runtime path acceptance; Qwen artifact identity is unavailable"

  defp snapshot_policy(true),
    do: "Strict Qwen snapshot acceptance belongs to the direct example eval fixture"

  defp snapshot_policy(false), do: "No Qwen logits snapshot is used without Qwen identity"
end
