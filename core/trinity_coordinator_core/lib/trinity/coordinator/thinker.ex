defmodule Trinity.Coordinator.Thinker do
  @moduledoc """
  Parser for TRINITY thinker suggestions.
  """

  alias Trinity.Coordinator.RoleInjector

  @enforce_keys [:raw]
  defstruct [:raw, :suggestion, :suggested_role, :suggested_role_id]

  @type t :: %__MODULE__{
          raw: String.t(),
          suggestion: String.t() | nil,
          suggested_role: String.t() | nil,
          suggested_role_id: non_neg_integer() | nil
        }

  @spec parse(String.t()) :: t()
  def parse(text) when is_binary(text) do
    suggestion = extract_tag(text, "suggestion")
    role = text |> extract_tag("suggested_role") |> normalize_suggested_role()

    if suggestion && role do
      %__MODULE__{
        raw: text,
        suggestion: suggestion,
        suggested_role: role,
        suggested_role_id: RoleInjector.role_id(role)
      }
    else
      %__MODULE__{raw: text, suggestion: nil, suggested_role: nil, suggested_role_id: nil}
    end
  end

  def parse(other), do: parse(to_string(other))

  defp extract_tag(text, tag) do
    open = "<" <> tag <> ">"
    close = "</" <> tag <> ">"

    case String.split(text, open, parts: 2) do
      [_before, rest] -> extract_closing_tag(rest, close)
      _ -> nil
    end
  end

  defp extract_closing_tag(rest, close) do
    case String.split(rest, close, parts: 2) do
      [value, _after] -> value |> String.trim() |> blank_to_nil()
      _ -> nil
    end
  end

  defp normalize_suggested_role(nil), do: nil

  defp normalize_suggested_role(role) do
    case role |> String.trim() |> String.downcase() do
      "solver" -> "Worker"
      "verifier" -> "Verifier"
      _ -> nil
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
