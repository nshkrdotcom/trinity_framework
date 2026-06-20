defmodule Trinity.Sakana.ReflexReplayReport do
  @moduledoc "Convenience aggregation for reflex economics inside fitness replay reports."

  @spec summarize([map()]) :: map()
  def summarize(examples) when is_list(examples) do
    examples
    |> Enum.group_by(&(get_in(&1, ["route", "reflex", "action"]) || "none"))
    |> Map.new(fn {action, rows} -> {action, %{"count" => length(rows)}} end)
  end
end
