defmodule Trinity.Coordinator.StateManager do
  @moduledoc """
  Minimal transcript state holder for coordinator-core loops.
  """

  use Agent

  @allowed_roles ["system", "user", "assistant"]

  @type message :: %{role: String.t(), content: String.t()}

  @spec start_link([map()]) :: Agent.on_start()
  def start_link(initial_messages \\ []) do
    Agent.start_link(fn -> normalize_messages!(initial_messages) end)
  end

  @spec get_messages(pid()) :: [message()]
  def get_messages(pid), do: Agent.get(pid, & &1)

  @spec append_message(pid(), String.t(), String.t()) :: :ok
  def append_message(pid, role, content) do
    message = normalize_message!(%{role: role, content: content})
    Agent.update(pid, &(&1 ++ [message]))
  end

  @spec append_user(pid(), String.t()) :: :ok
  def append_user(pid, content), do: append_message(pid, "user", content)

  @spec append_assistant(pid(), String.t()) :: :ok
  def append_assistant(pid, content), do: append_message(pid, "assistant", content)

  @spec append_system(pid(), String.t()) :: :ok
  def append_system(pid, content), do: append_message(pid, "system", content)

  defp normalize_messages!(messages) when is_list(messages),
    do: Enum.map(messages, &normalize_message!/1)

  defp normalize_messages!(_messages), do: raise(ArgumentError, "messages must be a list")

  defp normalize_message!(%{role: role, content: content}),
    do: validate_message!(%{role: role, content: content})

  defp normalize_message!(%{"role" => role, "content" => content}),
    do: validate_message!(%{role: role, content: content})

  defp normalize_message!(message),
    do: raise(ArgumentError, "invalid message #{inspect(message)}")

  defp validate_message!(%{role: role, content: content})
       when role in @allowed_roles and is_binary(content),
       do: %{role: role, content: content}

  defp validate_message!(message), do: raise(ArgumentError, "invalid message #{inspect(message)}")
end
