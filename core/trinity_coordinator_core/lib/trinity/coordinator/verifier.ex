defmodule Trinity.Coordinator.Verifier do
  @moduledoc """
  Parser for the TRINITY verifier ACCEPT/REVISE contract.
  """

  @enforce_keys [:status, :raw]
  defstruct [:status, :diagnosis, :raw, :token]

  @type status :: :accepted | :revised | :unknown
  @type t :: %__MODULE__{
          status: status(),
          diagnosis: String.t() | nil,
          raw: String.t(),
          token: String.t() | nil
        }

  @default_accept_token "ACCEPT"
  @default_revise_token "REVISE"

  @spec parse(String.t(), keyword()) :: t()
  def parse(text, opts \\ [])

  def parse(text, opts) when is_binary(text) and is_list(opts) do
    accept_token =
      opts
      |> Keyword.get(:accept_token, Keyword.get(opts, :stop_token, @default_accept_token))
      |> normalize_token()

    revise_token = opts |> Keyword.get(:revise_token, @default_revise_token) |> normalize_token()
    raw = String.trim(text)
    normalized = String.upcase(raw)

    cond do
      token_prefix?(normalized, accept_token) ->
        %__MODULE__{
          status: :accepted,
          raw: raw,
          token: accept_token,
          diagnosis: diagnosis_after_token(raw, accept_token)
        }

      token_prefix?(normalized, revise_token) ->
        %__MODULE__{
          status: :revised,
          raw: raw,
          token: revise_token,
          diagnosis: diagnosis_after_token(raw, revise_token)
        }

      true ->
        %__MODULE__{status: :unknown, raw: raw, token: nil, diagnosis: blank_to_nil(raw)}
    end
  end

  def parse(other, opts) when is_list(opts), do: parse(to_string(other), opts)

  @spec accepted?(String.t() | atom(), String.t(), keyword()) :: boolean()
  def accepted?(role, text, opts \\ [])

  def accepted?(role, text, opts) when is_binary(text) and is_list(opts) do
    verifier_role?(role) and safe_status(parse(text, opts)) == :accepted
  end

  def accepted?(_role, _text, _opts), do: false

  @spec safe_status(t()) :: :accepted | :revised
  def safe_status(%__MODULE__{status: :accepted}), do: :accepted
  def safe_status(%__MODULE__{status: :revised}), do: :revised
  def safe_status(%__MODULE__{status: :unknown}), do: :revised

  @spec verifier_role?(String.t() | atom()) :: boolean()
  def verifier_role?(role) when is_atom(role), do: role |> Atom.to_string() |> verifier_role?()

  def verifier_role?(role) when is_binary(role) do
    role
    |> String.trim()
    |> String.downcase()
    |> case do
      "verifier" -> true
      "v" -> true
      _ -> false
    end
  end

  def verifier_role?(_), do: false

  @spec trace_status(t()) :: status()
  def trace_status(%__MODULE__{status: status}), do: status

  defp normalize_token(token) when is_binary(token), do: token |> String.trim() |> String.upcase()
  defp normalize_token(token), do: token |> to_string() |> normalize_token()

  defp token_prefix?(_text, ""), do: false

  defp token_prefix?(text, token) do
    text == token or
      String.starts_with?(text, token <> ":") or
      String.starts_with?(text, token <> " ") or
      String.starts_with?(text, token <> "-") or
      String.starts_with?(text, token <> "\n") or
      String.starts_with?(text, token <> "\r\n")
  end

  defp diagnosis_after_token(raw, token) do
    raw
    |> binary_part_safe(byte_size(token))
    |> clean_leading_status_punctuation()
    |> blank_to_nil()
  end

  defp binary_part_safe(raw, skip) when byte_size(raw) <= skip, do: ""
  defp binary_part_safe(raw, skip), do: binary_part(raw, skip, byte_size(raw) - skip)

  defp clean_leading_status_punctuation(text) do
    text
    |> String.trim_leading()
    |> trim_many([":", "-"])
    |> String.trim()
  end

  defp trim_many(text, []), do: text

  defp trim_many(text, [prefix | rest]),
    do: text |> String.trim_leading(prefix) |> String.trim_leading() |> trim_many(rest)

  defp blank_to_nil(text), do: if(String.trim(text) == "", do: nil, else: String.trim(text))
end
