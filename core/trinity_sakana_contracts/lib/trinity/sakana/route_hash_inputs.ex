defmodule Trinity.Sakana.RouteHashInputs do
  @moduledoc """
  Hash input contract for Sakana route decisions and prompt transcripts.
  """

  @spec for_logits(non_neg_integer(), non_neg_integer(), [number()], [number()]) :: map()
  def for_logits(agent_id, role_id, agent_logits, role_logits)
      when is_integer(agent_id) and is_integer(role_id) and is_list(agent_logits) and
             is_list(role_logits) do
    %{
      "agent_id" => agent_id,
      "role_id" => role_id,
      "logits_rounded" => Enum.map(agent_logits ++ role_logits, &Float.round(&1, 6))
    }
  end

  @spec route_hash(non_neg_integer(), non_neg_integer(), [number()]) :: String.t()
  def route_hash(agent_id, role_id, logits_rounded) when is_list(logits_rounded) do
    [agent_id, role_id, logits_rounded]
    |> :erlang.term_to_binary([:compressed])
    |> sha256_hex()
  end

  @spec transcript_hash([map()]) :: String.t()
  def transcript_hash(messages) when is_list(messages) do
    messages
    |> Enum.map(fn message ->
      %{
        role: Map.get(message, :role, Map.get(message, "role")),
        content: Map.get(message, :content, Map.get(message, "content"))
      }
    end)
    |> :erlang.term_to_binary([:compressed])
    |> sha256_hex()
  end

  defp sha256_hex(binary) do
    :crypto.hash(:sha256, binary)
    |> Base.encode16(case: :lower)
  end
end
