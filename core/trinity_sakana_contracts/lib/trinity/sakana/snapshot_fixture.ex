defmodule Trinity.Sakana.SnapshotFixture do
  @moduledoc """
  Prompt-eval snapshot fixture contract.
  """

  @required_case_keys ~w(id agent_id role_id token_count transcript_hash)

  @spec validate(map()) :: {:ok, map()} | {:error, term()}
  def validate(%{"cases" => cases} = fixture) when is_list(cases) do
    case Enum.find_value(cases, &case_error/1) do
      nil -> {:ok, fixture}
      reason -> {:error, reason}
    end
  end

  def validate(value), do: {:error, {:invalid_snapshot_fixture, value}}

  defp case_error(%{} = case_spec) do
    case Enum.find(@required_case_keys, &(not Map.has_key?(case_spec, &1))) do
      nil -> nil
      key -> {:missing_snapshot_case_key, Map.get(case_spec, "id"), key}
    end
  end

  defp case_error(value), do: {:invalid_snapshot_case, value}
end
