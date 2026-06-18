defmodule Trinity.Ops.EvalMetadataTest do
  use ExUnit.Case, async: true

  alias Trinity.Ops.EvalMetadata

  @default_artifact_root Path.expand(
                           "../../../../../priv/sakana_trinity/adapted_qwen3_0_6b_layer26",
                           __DIR__
                         )

  test "mock_tiny reports a contract eval without Qwen" do
    metadata = EvalMetadata.matrix(:mock_tiny, @default_artifact_root)

    assert metadata.qwen_loaded? == false
    assert metadata.eval_mode == "mock_tiny contract eval"
    assert metadata.acceptance_level =~ "does not load Qwen"
    assert metadata.artifact_status == :mock
  end

  test "cuda_exla with Qwen artifact reports Qwen loaded" do
    metadata = EvalMetadata.matrix(:cuda_exla, @default_artifact_root)

    assert metadata.qwen_loaded? == true
    assert metadata.eval_mode == "CUDA Qwen route eval"
    assert metadata.model_id == "Qwen/Qwen3-0.6B"
    assert metadata.adapter_id == :trinity_qwen3_0_6b_sakana
    assert metadata.artifact_status == :available
  end

  test "custom non-Qwen artifact reports no Qwen identity" do
    root = Path.join(tmp_dir("custom"), "custom-artifact")
    File.mkdir_p!(root)

    write_json!(Path.join(root, "manifest.json"), %{
      "base_model_repo" => "example/non-qwen-router",
      "router_head_shape" => [4, 16]
    })

    metadata = EvalMetadata.matrix(:custom, root)

    assert metadata.qwen_loaded? == false
    assert metadata.eval_mode == "route runtime eval without Qwen artifact identity"
    assert metadata.model_id == "example/non-qwen-router"
    assert metadata.adapter_id == nil
    assert metadata.artifact_status == :available
  end

  test "binary profile without manifest reports unknown Qwen identity" do
    root = tmp_dir("missing")
    File.mkdir_p!(root)

    metadata = EvalMetadata.matrix(:binary, root)

    assert metadata.qwen_loaded? == false
    assert metadata.eval_mode == "route runtime eval without Qwen artifact identity"
    assert metadata.model_id == nil
    assert metadata.adapter_id == nil
    assert metadata.artifact_status == :missing
  end

  defp tmp_dir(name) do
    path = Path.join(System.tmp_dir!(), "trinity-eval-metadata-#{name}")
    File.rm_rf!(path)
    path
  end

  defp write_json!(path, payload) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(payload))
  end
end
