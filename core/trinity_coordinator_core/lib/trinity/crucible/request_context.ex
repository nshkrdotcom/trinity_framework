defmodule Trinity.Crucible.RequestContext do
  @moduledoc """
  Coordinator-owned input contract for building Crucible tap plans.
  """

  alias CrucibleSignalTrace.Digest

  @redacted "[REDACTED]"
  @secret_key_fragments ~w(authorization api_key apikey bearer credential password secret token)

  defstruct request_id: nil,
            run_id: nil,
            attempt_id: nil,
            session_id: nil,
            role: nil,
            candidate_routes: [],
            prompt_digest: nil,
            artifact_root: nil,
            trace_out: nil,
            policy_id: nil,
            messages: [],
            task_type: :unknown,
            turn: 0,
            budget_context: nil,
            trace_ref: nil,
            coordination_run_ref: nil,
            runtime_profile: nil,
            capabilities: [],
            metadata: %{}

  @type task_type ::
          :answer
          | :debug
          | :planning
          | :review
          | :verification
          | :creative
          | :unknown

  @type t :: %__MODULE__{
          request_id: String.t() | nil,
          run_id: String.t() | nil,
          attempt_id: String.t() | nil,
          session_id: String.t() | nil,
          role: String.t() | atom() | nil,
          candidate_routes: [term()],
          prompt_digest: String.t() | nil,
          artifact_root: String.t() | nil,
          trace_out: String.t() | nil,
          policy_id: String.t() | nil,
          messages: [map()],
          task_type: task_type(),
          turn: non_neg_integer(),
          budget_context: term(),
          trace_ref: String.t() | nil,
          coordination_run_ref: String.t() | nil,
          runtime_profile: term(),
          capabilities: [atom()],
          metadata: map()
        }

  @spec new(keyword() | map()) :: t()
  def new(attrs \\ []) when is_list(attrs) or is_map(attrs) do
    attrs = attrs_map(attrs)
    messages = field(attrs, :messages, [])

    %__MODULE__{
      request_id: field(attrs, :request_id),
      run_id: field(attrs, :run_id),
      attempt_id: field(attrs, :attempt_id),
      session_id: field(attrs, :session_id),
      role: field(attrs, :role),
      candidate_routes: normalize_list(field(attrs, :candidate_routes, [])),
      prompt_digest: field(attrs, :prompt_digest) || prompt_digest(messages),
      artifact_root: field(attrs, :artifact_root),
      trace_out: field(attrs, :trace_out),
      policy_id: field(attrs, :policy_id),
      messages: messages,
      task_type: normalize_task_type(field(attrs, :task_type) || infer_task_type(messages)),
      turn: normalize_turn(field(attrs, :turn, 0)),
      budget_context: field(attrs, :budget_context),
      trace_ref: field(attrs, :trace_ref),
      coordination_run_ref: field(attrs, :coordination_run_ref),
      runtime_profile: field(attrs, :runtime_profile),
      capabilities: normalize_capabilities(field(attrs, :capabilities, [])),
      metadata: field(attrs, :metadata, %{})
    }
  end

  @spec from_messages([map()], keyword() | map()) :: t()
  def from_messages(messages, attrs \\ []) when is_list(messages) do
    attrs
    |> attrs_map()
    |> Map.put(:messages, messages)
    |> new()
  end

  @spec transcript_text(t()) :: String.t()
  def transcript_text(%__MODULE__{messages: messages}) do
    messages
    |> Enum.map(&message_content/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  @spec redacted_metadata(t()) :: map()
  def redacted_metadata(%__MODULE__{metadata: metadata}) when is_map(metadata) do
    redact(metadata)
  end

  def redacted_metadata(%__MODULE__{}), do: %{}

  defp infer_task_type(messages) do
    text = messages |> Enum.map_join("\n", &message_content/1) |> String.downcase()

    cond do
      empty_prompt?(text) ->
        :verification

      keyword_hit?(text, ["worker answer", "verify", "check", "test has not"]) ->
        :verification

      keyword_hit?(text, ["review", "risk", "legal", "security"]) ->
        :review

      keyword_hit?(text, ["plan", "break", "decompos", "tradeoff"]) ->
        :planning

      keyword_hit?(text, ["bug", "debug", "sql", "refactor"]) ->
        :debug

      keyword_hit?(text, ["draft", "write", "opening lines"]) ->
        :creative

      true ->
        :answer
    end
  end

  defp empty_prompt?(text), do: text == "" or String.trim(text) in [".", "?"]

  defp keyword_hit?(text, keywords), do: Enum.any?(keywords, &String.contains?(text, &1))

  defp normalize_task_type(task_type)
       when task_type in [:answer, :debug, :planning, :review, :verification, :creative, :unknown],
       do: task_type

  defp normalize_task_type(task_type) when is_binary(task_type) do
    Map.get(task_type_aliases(), String.downcase(task_type), :unknown)
  end

  defp normalize_task_type(_task_type), do: :unknown

  defp task_type_aliases do
    %{
      "answer" => :answer,
      "debug" => :debug,
      "planning" => :planning,
      "plan" => :planning,
      "review" => :review,
      "verification" => :verification,
      "verify" => :verification,
      "creative" => :creative
    }
  end

  defp normalize_turn(turn) when is_integer(turn) and turn >= 0, do: turn
  defp normalize_turn(_turn), do: 0

  defp normalize_list(value) when is_list(value), do: value
  defp normalize_list(nil), do: []
  defp normalize_list(value), do: [value]

  defp normalize_capabilities(capabilities) when is_list(capabilities) do
    capabilities
    |> Enum.map(&normalize_capability/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_capabilities(_capabilities), do: []

  defp normalize_capability(capability) when is_atom(capability), do: capability

  defp normalize_capability(capability) when is_binary(capability) do
    case capability do
      "early_exit" -> :early_exit
      "custom_generation_loop" -> :custom_generation_loop
      "in_graph_steering" -> :in_graph_steering
      "logit_lens" -> :logit_lens
      "route_logits" -> :route_logits
      _ -> nil
    end
  end

  defp normalize_capability(_capability), do: nil

  defp message_content(%{content: content}) when is_binary(content), do: content
  defp message_content(%{"content" => content}) when is_binary(content), do: content
  defp message_content(_message), do: ""

  defp prompt_digest(messages) do
    text =
      messages
      |> Enum.map(&message_content/1)
      |> Enum.join("\n")

    if text == "", do: nil, else: Digest.prefixed_text(text)
  end

  defp redact(value) when is_map(value) do
    Map.new(value, fn {key, nested} ->
      if secret_key?(key), do: {key, @redacted}, else: {key, redact(nested)}
    end)
  end

  defp redact(value) when is_list(value), do: Enum.map(value, &redact/1)
  defp redact(value), do: value

  defp secret_key?(key) do
    key = key |> to_string() |> String.downcase()
    Enum.any?(@secret_key_fragments, &String.contains?(key, &1))
  end

  defp attrs_map(attrs) when is_list(attrs), do: Map.new(attrs)
  defp attrs_map(attrs) when is_map(attrs), do: attrs

  defp field(map, field, default \\ nil),
    do: Map.get(map, field, Map.get(map, Atom.to_string(field), default))
end
