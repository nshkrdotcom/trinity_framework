defmodule Trinity.Ops.EvalMetadataTest do
  use ExUnit.Case, async: true

  alias Trinity.Ops.EvalMetadata

  @fixture_artifact_root Path.expand(
                           "../../../../../apps/trinity_single_node/test/fixtures/artifacts/qwen_sakana_tiny",
                           __DIR__
                         )

  test "mock_tiny reports a contract eval without Qwen" do
    metadata = EvalMetadata.matrix(:mock_tiny, @fixture_artifact_root)

    assert metadata.qwen_loaded? == false
    assert metadata.qwen_artifact_ready? == false
    assert metadata.qwen_runtime_loaded? == false
    assert metadata.qwen_route_executed? == false
    assert metadata.eval_mode == "mock_tiny contract eval"
    assert metadata.acceptance_level =~ "does not load Qwen"
    assert metadata.artifact_status == :mock
  end

  test "cuda_exla with verified Qwen/Sakana artifact reports route readiness" do
    metadata = EvalMetadata.matrix(:cuda_exla, @fixture_artifact_root)

    assert metadata.qwen_loaded? == false
    assert metadata.qwen_artifact_ready? == true
    assert metadata.qwen_runtime_loaded? == false
    assert metadata.qwen_route_executed? == false
    assert metadata.qwen_base_model? == true
    assert metadata.sakana_route_artifact? == true
    assert metadata.artifact_available? == true
    assert metadata.artifact_pin_verified? == true
    assert metadata.eval_mode == "CUDA Qwen/Sakana route eval"
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
    assert metadata.qwen_artifact_ready? == false
    assert metadata.qwen_runtime_loaded? == false
    assert metadata.qwen_route_executed? == false
    assert metadata.eval_mode == "route runtime eval without Qwen artifact identity"
    assert metadata.model_id == "example/non-qwen-router"
    assert metadata.adapter_id == nil
    assert metadata.artifact_status == :available_unpinned
  end

  test "binary profile without manifest reports unknown Qwen identity" do
    root = tmp_dir("missing")
    File.mkdir_p!(root)

    metadata = EvalMetadata.matrix(:binary, root)

    assert metadata.qwen_loaded? == false
    assert metadata.qwen_artifact_ready? == false
    assert metadata.qwen_runtime_loaded? == false
    assert metadata.qwen_route_executed? == false
    assert metadata.eval_mode == "route runtime eval without Qwen artifact identity"
    assert metadata.model_id == nil
    assert metadata.adapter_id == nil
    assert metadata.artifact_status == :missing
  end

  test "matrix metadata can mark route execution observed after rows run" do
    metadata = EvalMetadata.matrix(:cuda_exla, @fixture_artifact_root)

    observed =
      EvalMetadata.with_execution_observed(metadata, [
        %{
          trace_id: "trace:eval-metadata",
          trace_model_id: "Qwen/Qwen3-0.6B",
          trace_signal_count: 1
        }
      ])

    assert observed.qwen_artifact_ready? == true
    assert observed.runtime_execution_observed? == true
    assert observed.qwen_runtime_loaded? == true
    assert observed.qwen_route_executed? == true
    assert observed.qwen_loaded? == true
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
