defmodule Trinity.SingleNode.ArtifactIdentityTest do
  use ExUnit.Case, async: true

  alias Trinity.SingleNode.ArtifactIdentity

  @fixture_artifact_root Path.expand("../../fixtures/artifacts/qwen_sakana_tiny", __DIR__)

  @default_artifact_root Path.expand(
                           "../../../../../priv/sakana_trinity/adapted_qwen3_0_6b_layer26",
                           __DIR__
                         )

  test "fixture Qwen/Sakana artifact identity verifies manifest pin" do
    identity = ArtifactIdentity.resolve(:cuda_exla, @fixture_artifact_root)
    actual_sha = sha256_file(Path.join(@fixture_artifact_root, "manifest.json"))

    assert identity.artifact_status == :available
    assert identity.artifact_status_reason == nil
    assert identity.artifact_available? == true
    assert identity.artifact_pin_verified? == true
    assert identity.qwen_base_model? == true
    assert identity.sakana_route_artifact? == true
    assert identity.qwen_loaded? == false
    assert ArtifactIdentity.qwen_route_ready?(identity) == true

    assert identity.adapter_id == :trinity_qwen3_0_6b_sakana
    assert identity.model_id == "Qwen/Qwen3-0.6B"
    assert identity.artifact_ref == "artifact:example_qwen-sakana-tiny:fixture-v1:79836c21c7df"
    assert identity.artifact_repo == "example/qwen-sakana-tiny"
    assert identity.artifact_revision == "fixture-v1"
    assert identity.artifact_manifest_sha256 == actual_sha
    assert identity.artifact_manifest_sha256_actual == actual_sha
    assert identity.artifact_pin_manifest_sha256 == actual_sha
    assert identity.artifact_pin_path == Path.join(@fixture_artifact_root, "artifact_pin.json")
    assert identity.router_head_shape == [10, 1024]
    assert identity.selected_tensor_count == 1
    assert identity.scale_offset_count == 1024
    assert identity.source_vector_shape == [11_264]
  end

  test "manifest provenance cannot be reshaped by caller options" do
    identity =
      ArtifactIdentity.resolve(:cuda_exla, @fixture_artifact_root,
        adapter_id: :spoofed_adapter,
        model_id: "example/spoofed-model",
        artifact_ref: "artifact:spoofed",
        artifact_repo: "example/spoofed-repo",
        artifact_revision: "spoofed-revision",
        manifest_status: "spoofed",
        artifact_layout: "spoofed",
        router_head_artifact: "spoofed.safetensors",
        router_head_shape: [1, 1],
        selected_tensor_count: 99,
        scale_offset_count: 99,
        source_vector_shape: [99]
      )

    assert identity.adapter_id == :trinity_qwen3_0_6b_sakana
    assert identity.model_id == "Qwen/Qwen3-0.6B"
    assert identity.artifact_ref == "artifact:example_qwen-sakana-tiny:fixture-v1:79836c21c7df"
    assert identity.artifact_repo == "example/qwen-sakana-tiny"
    assert identity.artifact_revision == "fixture-v1"
    assert identity.manifest_status == "complete"
    assert identity.artifact_layout == "test_fixture"
    assert identity.router_head_artifact == "router_head.safetensors"
    assert identity.router_head_shape == [10, 1024]
    assert identity.selected_tensor_count == 1
    assert identity.scale_offset_count == 1024
    assert identity.source_vector_shape == [11_264]
    assert ArtifactIdentity.qwen_route_ready?(identity) == true
  end

  test "mock runtime provenance is fixed by the framework contract" do
    identity =
      ArtifactIdentity.resolve(:mock_tiny, nil,
        adapter_id: :spoofed_adapter,
        model_id: "example/spoofed-model",
        artifact_ref: "artifact:spoofed",
        router_head_shape: [99, 99],
        selected_tensor_count: 99,
        scale_offset_count: 99,
        source_vector_shape: [99]
      )

    assert identity.adapter_id == :mock_tiny
    assert identity.model_id == "trinity/mock-tiny-route-runtime"
    assert identity.artifact_ref == "artifact:mock-tiny-route-runtime"
    assert identity.router_head_shape == [10, 8]
    assert identity.selected_tensor_count == 0
    assert identity.scale_offset_count == 0
    assert identity.source_vector_shape == []
  end

  @tag :qwen_artifact
  test "real default Qwen artifact identity is canonical when generated bundle is present" do
    manifest_path = Path.join(@default_artifact_root, "manifest.json")

    if File.regular?(manifest_path) do
      identity = ArtifactIdentity.resolve(:cuda_exla, @default_artifact_root)

      assert identity.artifact_status == :available
      assert identity.artifact_pin_verified? == true
      assert identity.qwen_base_model? == true
      assert identity.sakana_route_artifact? == true
      assert ArtifactIdentity.qwen_route_ready?(identity) == true
      assert identity.adapter_id == :trinity_qwen3_0_6b_sakana
      assert identity.model_id == "Qwen/Qwen3-0.6B"
      assert identity.artifact_ref == "artifact:qwen3-0.6b-sakana"
      assert identity.artifact_repo == "nshkrdotcom/trinity-coordinator-adapted-qwen3-0.6b"
      assert identity.artifact_revision == "v1.0.0"
      assert identity.artifact_manifest_sha256 == sha256_file(manifest_path)
      assert identity.artifact_manifest_sha256_actual == sha256_file(manifest_path)
      assert identity.artifact_pin_manifest_sha256 == sha256_file(manifest_path)
      assert identity.router_head_shape == [10, 1024]
      assert identity.selected_tensor_count == 9
      assert identity.scale_offset_count == 9216
      assert identity.source_vector_shape == [19_456]
    else
      assert true
    end
  end

  test "custom artifact root reports pin mismatch without trusting pin sha" do
    root = Path.join(tmp_dir("custom-artifact"), "custom-artifact")
    File.mkdir_p!(root)

    manifest_path = Path.join(root, "manifest.json")

    write_json!(manifest_path, %{
      "base_model_repo" => "example/non-qwen-router",
      "router_head_shape" => [4, 16],
      "selected_tensor_count" => 2,
      "scale_offset_count" => 12,
      "source_vector_shape" => [76]
    })

    pin_sha = String.duplicate("b", 64)

    write_json!(Path.join(Path.dirname(root), "artifact_pin.json"), %{
      "repo_id" => "example/custom-artifact",
      "revision" => "custom-v2",
      "manifest_sha256" => pin_sha
    })

    identity = ArtifactIdentity.resolve(:custom, root)
    actual_sha = sha256_file(manifest_path)

    assert identity.artifact_status == :pin_mismatch

    assert identity.artifact_status_reason ==
             "artifact pin manifest sha256 does not match manifest.json"

    assert identity.artifact_available? == false
    assert identity.artifact_pin_verified? == false
    assert identity.qwen_base_model? == false
    assert identity.sakana_route_artifact? == false
    assert identity.qwen_loaded? == false
    assert identity.adapter_id == nil
    assert identity.model_id == "example/non-qwen-router"

    assert identity.artifact_ref ==
             "artifact:example_custom-artifact:custom-v2:#{String.slice(actual_sha, 0, 12)}"

    assert identity.artifact_repo == "example/custom-artifact"
    assert identity.artifact_revision == "custom-v2"
    assert identity.artifact_manifest_sha256 == actual_sha
    assert identity.artifact_manifest_sha256_actual == actual_sha
    assert identity.artifact_pin_manifest_sha256 == pin_sha
    assert identity.router_head_shape == [4, 16]
    assert identity.selected_tensor_count == 2
    assert identity.scale_offset_count == 12
    assert identity.source_vector_shape == [76]
  end

  test "available unpinned Qwen/Sakana artifact is usable but not route-ready" do
    root = Path.join(tmp_dir("available-unpinned"), "qwen-artifact")
    manifest_path = Path.join(root, "manifest.json")
    write_json!(manifest_path, valid_qwen_manifest())

    identity = ArtifactIdentity.resolve(:cuda_exla, root)

    assert identity.artifact_status == :available_unpinned
    assert identity.artifact_status_reason == "artifact pin not found"
    assert identity.artifact_available? == true
    assert identity.artifact_pin_verified? == false
    assert identity.qwen_base_model? == true
    assert identity.sakana_route_artifact? == true
    assert ArtifactIdentity.qwen_route_ready?(identity) == false
  end

  test "pin without manifest sha is reported as pin_missing and not route-ready" do
    root = Path.join(tmp_dir("pin-missing"), "qwen-artifact")
    manifest_path = Path.join(root, "manifest.json")
    write_json!(manifest_path, valid_qwen_manifest())

    write_json!(Path.join(root, "artifact_pin.json"), %{
      "repo_id" => "example/qwen-sakana-pin-missing",
      "revision" => "fixture-v1"
    })

    identity = ArtifactIdentity.resolve(:cuda_exla, root)

    assert identity.artifact_status == :pin_missing
    assert identity.artifact_status_reason == "artifact pin does not include manifest sha256"
    assert identity.artifact_available? == false
    assert identity.artifact_pin_verified? == false
    assert identity.qwen_base_model? == true
    assert identity.sakana_route_artifact? == true
    assert ArtifactIdentity.qwen_route_ready?(identity) == false
  end

  test "invalid manifest json reports invalid_manifest with reason" do
    root = Path.join(tmp_dir("invalid-manifest"), "qwen-artifact")
    File.mkdir_p!(root)
    File.write!(Path.join(root, "manifest.json"), "{not-json")

    identity = ArtifactIdentity.resolve(:cuda_exla, root)

    assert identity.artifact_status == :invalid_manifest
    assert is_binary(identity.artifact_status_reason)
    assert identity.artifact_status_reason != ""
    assert identity.artifact_available? == false
    assert identity.sakana_route_artifact? == false
    assert ArtifactIdentity.qwen_route_ready?(identity) == false
  end

  test "incomplete Qwen manifest is not classified as a Sakana route artifact" do
    root = Path.join(tmp_dir("incomplete-qwen"), "qwen-artifact")

    write_json!(Path.join(root, "manifest.json"), %{
      "base_model_repo" => "Qwen/Qwen3-0.6B",
      "router_head_shape" => [10, 1024],
      "selected_tensor_count" => 1,
      "scale_offset_count" => 1024
    })

    identity = ArtifactIdentity.resolve(:cuda_exla, root)

    assert identity.qwen_base_model? == true
    assert identity.sakana_route_artifact? == false
    assert ArtifactIdentity.qwen_route_ready?(identity) == false
  end

  test "missing artifact manifest is reported as missing instead of default Qwen" do
    root = Path.join(tmp_dir("missing"), "missing-artifact")
    File.mkdir_p!(root)

    identity = ArtifactIdentity.resolve(:binary, root)

    assert identity.artifact_status == :missing
    assert identity.artifact_status_reason == "manifest.json not found"
    assert identity.artifact_available? == false
    assert identity.artifact_pin_verified? == false
    assert identity.qwen_base_model? == false
    assert identity.sakana_route_artifact? == false
    assert identity.qwen_loaded? == false
    assert identity.adapter_id == nil
    assert identity.model_id == nil
    assert identity.artifact_ref == "artifact:missing-artifact"
    assert identity.artifact_repo == nil
    assert identity.artifact_revision == nil
    assert identity.artifact_manifest_sha256 == nil
    assert identity.artifact_manifest_sha256_actual == nil
    assert identity.artifact_pin_manifest_sha256 == nil
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

  defp valid_qwen_manifest do
    %{
      "artifact_layout" => "test_fixture",
      "base_model_repo" => "Qwen/Qwen3-0.6B",
      "router_head_artifact" => "router_head.safetensors",
      "router_head_shape" => [10, 1024],
      "scale_offset_count" => 1024,
      "selected_tensor_count" => 1,
      "source_vector_shape" => [11_264],
      "status" => "complete"
    }
  end

  defp sha256_file(path) do
    path
    |> File.read!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
