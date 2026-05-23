defmodule Trinity.SakanaContractTest do
  use ExUnit.Case, async: true

  alias Trinity.Sakana.{
    Manifest,
    MarginDefaults,
    ParityReportSchema,
    RouteHashInputs,
    RouterHeadSpec,
    SLMProfileSpec,
    SnapshotFixture,
    StageName
  }

  test "manifest validates required keys, selected tensors, layout, and router-head shape" do
    manifest = manifest_fixture()

    assert {:ok, ^manifest} = Manifest.validate(manifest)
    assert {:ok, [selected]} = Manifest.selected_tensors(manifest)
    assert selected.path == "model.layers.26.mlp.gate_proj.weight"
    assert selected.artifact_key == selected.path

    assert {:error, {:missing_manifest_key, "artifact_version"}} =
             manifest |> Map.delete("artifact_version") |> Manifest.validate()

    assert {:error, {:selected_tensor_count_mismatch, expected: 2, actual: 1}} =
             manifest |> Map.put("selected_tensor_count", 2) |> Manifest.validate()
  end

  test "router head and SLM profile contracts carry canonical Qwen/Sakana dimensions" do
    assert {:ok, spec} =
             RouterHeadSpec.new(
               hidden_size: 1_024,
               num_agents: 7,
               num_roles: 3,
               router_head_shape: [10, 1_024]
             )

    assert RouterHeadSpec.output_count(spec) == 10

    profile = SLMProfileSpec.qwen3_0_6b_layer26()
    assert profile.base_model_repo == "Qwen/Qwen3-0.6B"
    assert profile.hidden_size == 1_024
    assert profile.selected_layer_indices == [26]
  end

  test "stage names and tolerances match the parity contract" do
    assert StageName.names() == [
             "source_f32",
             "offsets_f32",
             "scaled_s",
             "normalization",
             "u_scaled",
             "matmul_pre_norm",
             "zero_source_f32",
             "adapted_source_f32",
             "final_f32",
             "final_bf16"
           ]

    assert StageName.required?("stage.final_f32")
    refute StageName.required?("stage.final_bf16")

    assert StageName.tolerance("stage.source_f32") == %{
             required?: true,
             max_abs: 0.0,
             mean_abs: 0.0
           }
  end

  test "route and transcript hash inputs reproduce the coordinator fixture contract" do
    agent_logits = [15.854443, 9.122092, 4.819489, 0.056395, 30.22077, -23.630211, 10.418853]
    role_logits = [-7.696819, -15.208102, 4.941882]

    inputs = RouteHashInputs.for_logits(4, 2, agent_logits, role_logits)

    assert inputs["logits_rounded"] == agent_logits ++ role_logits

    assert RouteHashInputs.route_hash(4, 2, inputs["logits_rounded"]) ==
             "a6f10d75a70ca4bca93f1c3a689365f28bcc9b293e25ac9643166dc980efcefe"

    assert RouteHashInputs.transcript_hash([
             %{"role" => "user", "content" => "What is 17 + 25? Answer briefly."}
           ]) ==
             "05485d3e42e7b2e0c63bad13d446915173499b5a9a980faff24195c33bdbf0b3"
  end

  test "snapshot fixtures, margin defaults, and parity reports validate JSON-safe shapes" do
    assert MarginDefaults.defaults(:cuda_exla) == %{agent: 0.24, role: 1.06}

    snapshot = %{
      "cases" => [
        %{
          "id" => "math_direct",
          "agent_id" => 4,
          "role_id" => 2,
          "token_count" => 15,
          "transcript_hash" => "sha256:transcript"
        }
      ]
    }

    assert {:ok, ^snapshot} = SnapshotFixture.validate(snapshot)

    assert :ok =
             ParityReportSchema.validate_stage_checks([
               %{
                 "stage" => "stage.source_f32",
                 "required_for_functional_parity" => true,
                 "functional_passed" => true
               }
             ])
  end

  defp manifest_fixture do
    %{
      "artifact_version" => 1,
      "status" => "complete",
      "selected_tensors" => [
        %{
          "path" => "model.layers.26.mlp.gate_proj.weight",
          "artifact_key" => "model.layers.26.mlp.gate_proj.weight",
          "shape" => [2048, 1024],
          "singular_values" => 512,
          "type" => "matrix",
          "segments" => []
        }
      ],
      "adapted_tensors_artifact" => "adapted_tensors.safetensors",
      "router_head_artifact" => "router_head.safetensors",
      "router_head_shape" => [10, 1024],
      "artifact_layout" => "checkpoint_directory",
      "selected_tensor_count" => 1,
      "selected_singular_value_count" => 512,
      "source_vector_shape" => [19_456],
      "source_vector_sha256" => "sha256:source",
      "scale_offset_count" => 9_216,
      "router_head_tensor_key" => "trinity_router_head",
      "base_model_repo" => "Qwen/Qwen3-0.6B",
      "architecture" => "for_causal_language_modeling",
      "xla_target" => "cuda12",
      "export_backend" => "elixir_nx_exla_cuda",
      "source_vector_path" =>
        "priv/sakana_trinity/artifacts/trinity_router_es_vector.safetensors",
      "source_vector_tensor" => "trinity_router_es_vector",
      "export_complete" => true,
      "source_split" => "layer26",
      "split" => "layer26"
    }
  end
end
