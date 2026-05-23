defmodule Trinity.Sakana.ParityReportSchema do
  @moduledoc """
  JSON-safe parity report contract for Sakana diagnostics.
  """

  @spec validate_stage_checks([map()]) :: :ok | {:error, term()}
  def validate_stage_checks(checks) when is_list(checks) do
    case Enum.find(checks, &(not valid_stage_check?(&1))) do
      nil -> :ok
      check -> {:error, {:invalid_stage_check, check}}
    end
  end

  def validate_stage_checks(value), do: {:error, {:invalid_stage_checks, value}}

  defp valid_stage_check?(%{} = check) do
    is_binary(Map.get(check, "stage")) and
      is_boolean(Map.get(check, "required_for_functional_parity")) and
      Map.has_key?(check, "functional_passed")
  end

  defp valid_stage_check?(_check), do: false
end
