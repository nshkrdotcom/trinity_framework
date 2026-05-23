defmodule Trinity.Bridge.Trace.JSONL do
  @moduledoc """
  Coordinator-compatible JSONL normalization backed by `AITrace.JSONL`.
  """

  defdelegate append(path, event), to: AITrace.JSONL
  defdelegate encode_line(event), to: AITrace.JSONL
  defdelegate normalize_for_json(value), to: AITrace.JSONL
end
