defmodule Trinity.CoordinatorCore do
  @moduledoc """
  The TRINITY orchestration state machine core.
  """

  alias Trinity.Coordinator.{Budgets, Orchestrator, RoleInjector, StateManager, Verifier}

  defdelegate start_state(initial_messages \\ []), to: StateManager, as: :start_link
  defdelegate run_loop(messages_or_pid, opts \\ []), to: Orchestrator
  defdelegate inject_role(messages, role), to: RoleInjector
  defdelegate verifier_accepted?(role, text, opts \\ []), to: Verifier, as: :accepted?
  defdelegate check_budgets(run_ctx, checkpoint, extras \\ %{}), to: Budgets, as: :check
end
