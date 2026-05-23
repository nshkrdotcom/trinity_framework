defmodule Trinity.Validation do
  @moduledoc false

  @forbidden_raw_fields [
    :raw_prompt,
    :prompt,
    :memory_body,
    :provider_payload,
    :tool_body,
    :model_output,
    :api_key,
    :authorization_header,
    :secret,
    :credential_body,
    :token_file
  ]

  def forbidden_raw_fields, do: @forbidden_raw_fields

  def reject_forbidden_raw_fields(%{} = attrs) do
    case Enum.find(@forbidden_raw_fields, &present_key?(attrs, &1)) do
      nil -> :ok
      field -> {:error, {:forbidden_raw_field, field}}
    end
  end

  def reject_forbidden_raw_fields(_attrs), do: {:error, :invalid_attrs}

  def require_binary(attrs, key) do
    case fetch(attrs, key) do
      value when is_binary(value) ->
        value = String.trim(value)

        if value == "" do
          {:error, {:blank_required_field, key}}
        else
          {:ok, value}
        end

      nil ->
        {:error, {:missing_required_field, key}}

      _other ->
        {:error, {:invalid_required_field, key}}
    end
  end

  def optional_binary(attrs, key) do
    case fetch(attrs, key) do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: {:ok, nil}, else: {:ok, value}

      nil ->
        {:ok, nil}

      _other ->
        {:error, {:invalid_optional_field, key}}
    end
  end

  def require_list(attrs, key) do
    case fetch(attrs, key) do
      values when is_list(values) ->
        {:ok, values}

      nil ->
        {:error, {:missing_required_field, key}}

      _other ->
        {:error, {:invalid_required_field, key}}
    end
  end

  def optional_list(attrs, key, default \\ []) do
    case fetch(attrs, key) do
      values when is_list(values) -> {:ok, values}
      nil -> {:ok, default}
      _other -> {:error, {:invalid_optional_field, key}}
    end
  end

  def require_map(attrs, key) do
    case fetch(attrs, key) do
      value when is_map(value) -> {:ok, value}
      nil -> {:error, {:missing_required_field, key}}
      _other -> {:error, {:invalid_required_field, key}}
    end
  end

  def optional_map(attrs, key, default \\ %{}) do
    case fetch(attrs, key) do
      value when is_map(value) -> {:ok, value}
      nil -> {:ok, default}
      _other -> {:error, {:invalid_optional_field, key}}
    end
  end

  def fetch(%{} = attrs, key) when is_atom(key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(attrs, key) -> Map.get(attrs, key)
      Map.has_key?(attrs, string_key) -> Map.get(attrs, string_key)
      true -> nil
    end
  end

  def present_key?(%{} = attrs, key) when is_atom(key) do
    Map.has_key?(attrs, key) or Map.has_key?(attrs, Atom.to_string(key))
  end
end
