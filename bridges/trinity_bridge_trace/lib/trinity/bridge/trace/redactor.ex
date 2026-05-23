defmodule Trinity.Bridge.Trace.Redactor do
  @moduledoc """
  TRINITY trace redaction wrapper over `AITrace.Redactor`.
  """

  defdelegate redact(value, mode), to: AITrace.Redactor
  defdelegate redact_values(value, values), to: AITrace.Redactor
end
