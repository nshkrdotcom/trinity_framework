defmodule Trinity.Bridge.Trace.Hash do
  @moduledoc """
  Coordinator-compatible trace hashing backed by `AITrace.Hash`.
  """

  defdelegate term(value), to: AITrace.Hash
  defdelegate messages(messages), to: AITrace.Hash
  defdelegate text(value), to: AITrace.Hash
  defdelegate metadata(map), to: AITrace.Hash
end
