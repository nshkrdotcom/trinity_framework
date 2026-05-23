defmodule Trinity.Bridge.Trace do
  @moduledoc """
  Trace export adapters.
  """

  alias Trinity.Bridge.Trace.JsonlSink

  @doc "Emits a coordinator trace event through the default JSONL sink."
  defdelegate emit(event, opts \\ []), to: JsonlSink
end
