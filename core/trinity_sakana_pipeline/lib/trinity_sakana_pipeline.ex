defmodule Trinity.SakanaPipeline do
  @moduledoc """
  TRINITY-specific Sakana/Qwen pipeline plan.
  """

  alias Trinity.SakanaPipeline.{ArtifactIO, Exporter, LargeTensorChunks, ParityTrace, StageCheck}

  defdelegate manifest_file(), to: ArtifactIO
  defdelegate router_head_file(), to: ArtifactIO
  defdelegate adapted_tensors_file(), to: ArtifactIO
  defdelegate checkpoint_directory_name(), to: ArtifactIO
  defdelegate file_sha256!(path), to: ArtifactIO

  defdelegate build_selected_tensors(selected, opts \\ []), to: Exporter
  defdelegate checkpoint_file(index, path), to: Exporter
  defdelegate finalize_manifest(manifest), to: Exporter

  defdelegate stage_names(), to: ParityTrace
  defdelegate tensor_stage_key(source_name, stage_name), to: ParityTrace

  defdelegate compare_stage_tensors(stage_tensors, reference_stage_tensors, opts \\ []),
    to: StageCheck

  defdelegate chunk_plan(row_count, opts \\ []), to: LargeTensorChunks
end
