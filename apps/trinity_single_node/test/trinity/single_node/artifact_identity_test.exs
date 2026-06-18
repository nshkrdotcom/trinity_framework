defmodule Trinity.SingleNode.ArtifactIdentityTest do
  use ExUnit.Case, async: true

  alias Trinity.SingleNode.ArtifactIdentity

  @default_artifact_root Path.expand(
                           "../../../../../priv/sakana_trinity/adapted_qwen3_0_6b_layer26",
                           __DIR__
                         )

  test "default Qwen artifact identity comes from manifest and pin" do
    identity = ArtifactIdentity.resolve(:cuda_exla, @default_artifact_root)

    assert identity.artifact_status == :available
    assert identity.qwen_loaded? == true
    assert identity.adapter_id == :trinity_qwen3_0_6b_sakana
    assert identity.model_id == "Qwen/Qwen3-0.6B"
    assert identity.artifact_ref == "artifact:qwen3-0.6b-sakana"
    assert identity.artifact_repo == "nshkrdotcom/trinity-coordinator-adapted-qwen3-0.6b"
    assert identity.artifact_revision == "v1.0.0"

    assert identity.artifact_manifest_sha256 ==
             "2a1476a4d2c7b66633232a564114dfb7ebe46f6bea624fc9ae9123678cafcbb9"

    assert identity.router_head_shape == [10, 1024]
    assert identity.selected_tensor_count == 9
    assert identity.scale_offset_count == 9216
    assert identity.source_vector_shape == [19_456]
  end

  test "custom artifact root uses actual manifest and sibling pin values" do
    root = Path.join(tmp_dir("custom-artifact"), "custom-artifact")
    File.mkdir_p!(root)

    write_json!(Path.join(root, "manifest.json"), %{
      "base_model_repo" => "example/non-qwen-router",
      "router_head_shape" => [4, 16],
      "selected_tensor_count" => 2,
      "scale_offset_count" => 12,
      "source_vector_shape" => [76]
    })

    write_json!(Path.join(Path.dirname(root), "artifact_pin.json"), %{
      "repo_id" => "example/custom-artifact",
      "revision" => "custom-v2",
      "manifest_sha256" => String.duplicate("b", 64)
    })

    identity = ArtifactIdentity.resolve(:custom, root)

    assert identity.artifact_status == :available
    assert identity.qwen_loaded? == false
    assert identity.adapter_id == nil
    assert identity.model_id == "example/non-qwen-router"
    assert identity.artifact_ref == "artifact:custom-artifact"
    assert identity.artifact_repo == "example/custom-artifact"
    assert identity.artifact_revision == "custom-v2"
    assert identity.artifact_manifest_sha256 == String.duplicate("b", 64)
    assert identity.router_head_shape == [4, 16]
    assert identity.selected_tensor_count == 2
    assert identity.scale_offset_count == 12
    assert identity.source_vector_shape == [76]
  end

  test "missing artifact manifest is reported as missing instead of default Qwen" do
    root = Path.join(tmp_dir("missing"), "missing-artifact")
    File.mkdir_p!(root)

    identity = ArtifactIdentity.resolve(:binary, root)

    assert identity.artifact_status == :missing
    assert identity.qwen_loaded? == false
    assert identity.adapter_id == nil
    assert identity.model_id == nil
    assert identity.artifact_ref == "artifact:missing-artifact"
    assert identity.artifact_repo == nil
    assert identity.artifact_revision == nil
    assert identity.artifact_manifest_sha256 == nil
  end

  defp tmp_dir(name) do
    path = Path.join(System.tmp_dir!(), "trinity-artifact-identity-#{name}")
    File.rm_rf!(path)
    path
  end

  defp write_json!(path, payload) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(payload))
  end
end
