defmodule Trinity.SakanaPipelineTest do
  use ExUnit.Case, async: true

  alias Trinity.Sakana.Manifest
  alias Trinity.SakanaPipeline

  alias Trinity.SakanaPipeline.{
    ArtifactIO,
    Exporter,
    LargeTensorChunks,
    ParityTrace,
    PythonImporter,
    StageCheck
  }

  test "builds selected tensor export entries in deterministic checkpoint order" do
    selected = [
      %{
        path: "decoder.blocks.26.ffn.gate.kernel",
        segments: [:decoder, :gate],
        tensor: Nx.iota({3, 2})
      },
      %{path: "lm_head.weight", segments: ["lm_head"], tensor: Nx.iota({5, 2})}
    ]

    entries = Exporter.build_selected_tensors(selected, svd_compute_type: :f32)

    assert Enum.map(entries, & &1["index"]) == [1, 2]
    assert Enum.map(entries, & &1["offset_start"]) == [0, 2]
    assert Enum.map(entries, & &1["offset_end"]) == [2, 4]
    assert Enum.map(entries, & &1["singular_values"]) == [2, 2]

    assert hd(entries)["checkpoint_path"] ==
             "checkpoints/0001_decoder.blocks.26.ffn.gate.kernel.safetensors"

    assert List.last(entries)["checkpoint_path"] == "checkpoints/0002_lm_head.weight.safetensors"
    assert Enum.all?(entries, &(&1["status"] == Exporter.status_pending()))
  end

  test "manifest seed preserves the qwen layer-26 Sakana contract" do
    selected = [%{path: "model.layers.26.mlp.gate_proj.weight", tensor: Nx.iota({2, 2})}]

    manifest =
      Exporter.manifest_seed(
        selected: selected,
        source_vector_shape: [19_456],
        source_vector_sha256: String.duplicate("a", 64),
        now: fn -> ~U[2026-05-22 00:00:00Z] end
      )

    assert manifest["artifact_version"] == 1
    assert manifest["router_head_shape"] == [10, 1024]
    assert manifest["scale_offset_count"] == 9_216
    assert manifest["selected_tensor_count"] == 1
    assert manifest["selected_singular_value_count"] == 2
    assert {:ok, ^manifest} = Manifest.validate(manifest)

    complete =
      manifest
      |> put_in(["selected_tensors", Access.at(0), "status"], Exporter.status_complete())
      |> Exporter.finalize_manifest()

    assert complete["status"] == "complete"
    assert complete["export_complete"]
  end

  @tag :tmp_dir
  test "artifact IO writes and reads safetensors without coordinator modules", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "tensor.safetensors")
    tensor = Nx.tensor([[1.0, 2.0], [3.0, 4.0]], type: :f32)

    assert ^path = ArtifactIO.write_tensors!(path, %{"demo" => tensor})
    assert sha256?(ArtifactIO.file_sha256!(path))

    restored = ArtifactIO.read_tensor!(path, "demo")
    assert Nx.shape(restored) == {2, 2}
    assert Nx.to_flat_list(restored) == [1.0, 2.0, 3.0, 4.0]
  end

  defp sha256?(value) when is_binary(value) do
    byte_size(value) == 64 and Enum.all?(String.to_charlist(value), &hex_char?/1)
  end

  defp sha256?(_value), do: false
  defp hex_char?(char), do: char in ?0..?9 or char in ?a..?f

  test "python importer normalizes Sakana selected tensors with fallback mapping" do
    manifest = %{
      "selected_tensors" => [
        %{
          "source_name" => "model.layers.26.mlp.gate_proj.weight",
          "shape" => [2, 3],
          "component_tensors" => %{"U" => "u.custom"},
          "offset_start" => 7,
          "offset_end" => 9
        }
      ]
    }

    [entry] = PythonImporter.normalize_selected_entries(manifest)

    assert entry["path"] == "decoder.blocks.26.ffn.gate.kernel"
    assert entry["safe_key"] == "model.layers.26.mlp.gate_proj.weight"
    assert entry["component_tensors"]["u"] == "u.custom"
    assert entry["component_tensors"]["s"] == "svd.S.model.layers.26.mlp.gate_proj.weight"
    assert entry["scale_tensor"] == "svf.scale_offsets.model.layers.26.mlp.gate_proj.weight"
    assert entry["python_v_layout"] == "torch_v"
  end

  test "large tensor chunk plans and parity summaries stay TRINITY-specific" do
    chunks = LargeTensorChunks.chunk_plan(5, chunk_rows: 2)

    assert chunks == [
             %{"chunk_index" => 1, "row_start" => 0, "row_end" => 2},
             %{"chunk_index" => 2, "row_start" => 2, "row_end" => 4},
             %{"chunk_index" => 3, "row_start" => 4, "row_end" => 5}
           ]

    assert LargeTensorChunks.large_source?("lm_head.weight")
    assert LargeTensorChunks.sanitize_python_key("model/layers.26:mlp") == "model__layers.26__mlp"

    assert LargeTensorChunks.summary([
             %{
               "checks" => [
                 %{"required_for_functional_parity" => true, "functional_passed" => true}
               ]
             }
           ])["functional_parity_passed"]
  end

  test "parity trace helpers preserve canonical Sakana constants and namespaced keys" do
    assert ParityTrace.router_vector_path() ==
             "priv/sakana_trinity/artifacts/trinity_router_es_vector.safetensors"

    assert ParityTrace.reference_manifest_path() ==
             "priv/sakana_trinity/reference/sakana_python_reference_manifest.json"

    assert ParityTrace.scale_count() == 9_216
    assert ParityTrace.hidden_size() == 1_024
    assert ParityTrace.output_count() == 10

    assert ParityTrace.semantic_layouts(%{"component_v_layout" => "vh"}, true) == [
             :vh,
             :torch_v,
             :nx
           ]

    assert ParityTrace.tensor_stage_key("model/lm:head", "stage.final_f32") ==
             "tensor.model__lm__head.stage.final_f32"
  end

  test "stage check delegates comparison to crucible factorization" do
    computed = %{"stage.source_f32" => Nx.tensor([1.0, 2.0], type: :f32)}
    reference = %{"stage.source_f32" => Nx.tensor([1.0, 2.0], type: :f32)}

    [check] =
      StageCheck.compare_stage_tensors(computed, reference,
        include_alt_hashes: false,
        include_tensor_summaries: false
      )

    assert check["functional_passed"]
    assert StageCheck.checks_passed?([check])
    assert StageCheck.required?("stage.source_f32")
    assert StageCheck.tolerance("stage.final_bf16").required? == false
  end

  test "root module exposes the pipeline surface" do
    assert SakanaPipeline.manifest_file() == ArtifactIO.manifest_file()
    assert SakanaPipeline.checkpoint_file(1, "a/b") == "0001_a_b.safetensors"

    assert SakanaPipeline.chunk_plan(1) == [
             %{"chunk_index" => 1, "row_start" => 0, "row_end" => 1}
           ]
  end
end
