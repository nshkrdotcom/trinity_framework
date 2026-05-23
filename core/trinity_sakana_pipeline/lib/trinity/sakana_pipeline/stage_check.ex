defmodule Trinity.SakanaPipeline.StageCheck do
  @moduledoc """
  TRINITY Sakana stage-check facade over Crucible factorization comparisons.
  """

  alias Trinity.Sakana.StageName

  @spec compare_stage_tensors(map(), map() | nil, keyword()) :: [map()]
  def compare_stage_tensors(stage_tensors, reference_stage_tensors, opts \\ []) do
    CrucibleFactorization.StageCheck.compare_stage_tensors(
      stage_tensors,
      reference_stage_tensors,
      opts
    )
  end

  @spec checks_passed?([map()]) :: boolean() | nil
  def checks_passed?(checks), do: CrucibleFactorization.StageCheck.checks_passed?(checks)

  @spec tensor_summary(Nx.Tensor.t(), keyword()) :: map()
  def tensor_summary(tensor, opts \\ []),
    do: CrucibleFactorization.StageCheck.tensor_summary(tensor, opts)

  @spec tolerance(String.t()) :: map()
  def tolerance(stage_name), do: StageName.tolerance(stage_name)

  @spec required?(String.t()) :: boolean()
  def required?(stage_name), do: StageName.required?(stage_name)
end
