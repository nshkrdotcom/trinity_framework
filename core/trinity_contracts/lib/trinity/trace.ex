defmodule Trinity.Trace do
  @moduledoc """
  Trace ref helper for router and session events.
  """

  def ref(coordination_run_ref, event_ref)
      when is_binary(coordination_run_ref) and is_binary(event_ref),
      do: "trace:" <> coordination_run_ref <> ":" <> event_ref
end
