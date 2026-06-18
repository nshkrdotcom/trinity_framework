defmodule Trinity.RefSanitizer do
  @moduledoc """
  Fixed-character reference fragment sanitizer.

  TRINITY refs are runtime-visible identifiers. Keep sanitization centralized so
  artifact refs, policy refs, and generated filenames do not drift over time.
  """

  @type option ::
          {:allow_colon?, boolean()}
          | {:fallback, String.t()}
          | {:trim?, boolean()}

  @spec safe_fragment(term(), [option()]) :: String.t()
  def safe_fragment(value, opts \\ [])

  def safe_fragment(nil, opts) do
    Keyword.get(opts, :fallback, "")
  end

  def safe_fragment(value, opts) do
    allow_colon? = Keyword.get(opts, :allow_colon?, true)
    fallback = Keyword.get(opts, :fallback, "")
    trim? = Keyword.get(opts, :trim?, false)

    value
    |> to_string()
    |> String.graphemes()
    |> Enum.map_join(fn char ->
      if safe_ref_char?(char, allow_colon?), do: char, else: "_"
    end)
    |> collapse_underscores()
    |> maybe_trim(trim?)
    |> case do
      "" -> fallback
      safe -> safe
    end
  end

  @spec collapse_underscores(String.t()) :: String.t()
  def collapse_underscores(value), do: collapse_underscores(value, "", false)

  defp maybe_trim(value, true), do: String.trim(value, "_")
  defp maybe_trim(value, false), do: value

  defp safe_ref_char?(<<char::utf8>>, allow_colon?) do
    ascii_letter?(char) or ascii_digit?(char) or char in allowed_punctuation(allow_colon?)
  end

  defp safe_ref_char?(_char, _allow_colon?), do: false

  defp allowed_punctuation(true), do: [45, 46, 58, 95]
  defp allowed_punctuation(false), do: [45, 46, 95]

  defp collapse_underscores("", acc, _previous?), do: acc

  defp collapse_underscores("_" <> rest, acc, true), do: collapse_underscores(rest, acc, true)

  defp collapse_underscores("_" <> rest, acc, false),
    do: collapse_underscores(rest, acc <> "_", true)

  defp collapse_underscores(<<char::utf8, rest::binary>>, acc, _previous?),
    do: collapse_underscores(rest, acc <> <<char::utf8>>, false)

  defp ascii_letter?(char), do: char in ?A..?Z or char in ?a..?z
  defp ascii_digit?(char), do: char in ?0..?9
end
