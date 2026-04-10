defmodule JidoHiveConsole.HelpGuide do
  @moduledoc false

  alias JidoHiveConsole.{Model, Projection}
  alias JidoHiveConsole.Screens.Publish

  @spec title(Model.t()) :: String.t()
  def title(%Model{active_screen: :lobby}), do: "Lobby Help"
  def title(%Model{active_screen: :room}), do: "Room Help"
  def title(%Model{active_screen: :conflict}), do: "Conflict Help"
  def title(%Model{active_screen: :publish}), do: "Publish Help"
  def title(%Model{active_screen: :wizard}), do: "Wizard Help"
  def title(%Model{active_screen: screen}), do: "#{screen} Help"

  @spec lines(Model.t()) :: [String.t()]
  def lines(%Model{active_screen: :lobby} = state), do: lobby_lines(state)
  def lines(%Model{active_screen: :room} = state), do: room_lines(state)
  def lines(%Model{active_screen: :conflict} = state), do: conflict_lines(state)
  def lines(%Model{active_screen: :publish} = state), do: publish_lines(state)
  def lines(%Model{active_screen: :wizard} = state), do: wizard_lines(state)

  def lines(%Model{}) do
    render_sections([
      {"Global", global_help_lines()}
    ])
  end

  defp lobby_lines(state) do
    render_sections([
      {"What this screen does",
       [
         "Continue an existing room or start a new guided room.",
         "Saved room ids come from ~/.config/hive/rooms.json for the current server."
       ]},
      {"Current state",
       [
         "Saved rooms loaded: #{length(state.lobby_rooms)}.",
         "Highlighted room: #{highlighted_room_label(state)}."
       ]},
      {"Keys for this screen",
       [
         "Up/Down moves the highlight. Enter opens the highlighted room.",
         "n starts the new-room wizard. r refreshes room summaries from the server.",
         "d removes a stale local entry when the saved room no longer exists on this server."
       ]},
      {"Workflow",
       [
         "Open a saved room when you want to inspect shared graph progress, steer the room, or publish a ready result.",
         "If a row shows a fetch error, remove it locally with d and recreate it from the server later if needed."
       ]},
      {"Global", global_help_lines()}
    ])
  end

  defp room_lines(state) do
    render_sections([
      {"What this screen does",
       [
         "This is the operator control plane for one room: understand workflow truth, review the focus queue, inspect the shared graph, and steer the room with human input."
       ]},
      {"Current state",
       [
         "Room: #{state.room_id || "none"}.",
         "Workflow stage: #{room_stage_label(state)}.",
         "Selected context: #{selected_context_label(state)}.",
         "Relation mode: #{Atom.to_string(state.relation_mode)}. Focused pane: #{state.pane_focus}.",
         "Draft: #{draft_summary(state)}.",
         "Enter right now: #{room_enter_summary(state)}."
       ]},
      {"Keys for this screen",
       [
         "Type to edit the composer. Plain letters never quit the console.",
         "Up/Down changes the selected context object. Tab cycles pane focus. Enter sends the draft or opens conflict resolution when the draft is empty and the selection is a contradiction.",
         "Ctrl+J inserts a newline without sending.",
         "Ctrl+N plain chat. Ctrl+T contextual. Ctrl+F references. Ctrl+D derives_from. Ctrl+S supports. Ctrl+X contradicts. Ctrl+V resolves.",
         "Ctrl+E traces why the selected object exists. Ctrl+A accepts the selected object. Ctrl+R refreshes the room. Ctrl+P opens publish. Ctrl+B returns to the lobby."
       ]},
      {"Workflow",
       [
         "Read the Workflow pane first. It is the room's server-backed summary of stage, blockers, next action, and current focus queue.",
         "Use the Shared Graph and Selected Review panes to inspect one item in detail before you accept it, resolve it, or steer around it.",
         "Use provenance when you need to understand why an object exists, and use publish only after the room reaches publication_ready."
       ]},
      {"Global", global_help_lines()}
    ])
  end

  defp conflict_lines(state) do
    render_sections([
      {"What this screen does",
       [
         "Resolve a contradiction surfaced by the shared graph by choosing one side or writing a synthesis."
       ]},
      {"Current state",
       [
         "Left side: #{context_id(state.conflict_left)}.",
         "Right side: #{context_id(state.conflict_right)}.",
         "Draft: #{if(String.trim(state.conflict_input_buf) == "", do: "empty", else: "#{String.length(state.conflict_input_buf)} chars entered")}."
       ]},
      {"Keys for this screen",
       [
         "Type a final decision in the draft box.",
         "a prefills an accept-left decision. b prefills an accept-right decision. s asks the system for an AI synthesis draft.",
         "Enter submits the resolution. Esc cancels and returns to the room."
       ]},
      {"Workflow",
       [
         "Accept one side when it is clearly correct. Use a synthesis only when both sides contain useful information that should be merged into a new resolving statement.",
         "If you need to understand where either side came from first, return to the room and inspect provenance before resolving."
       ]},
      {"Global", global_help_lines()}
    ])
  end

  defp publish_lines(state) do
    render_sections([
      {"What this screen does",
       [
         "Publish the room result into one or more external channels once the room is ready."
       ]},
      {"Current state",
       [
         "Room ready: #{publish_ready_label(state)}.",
         "Selected channels: #{selected_channels(state)}.",
         "Focused item: #{publish_focus_label(state)}.",
         "Auth summary: #{publish_auth_summary(state)}."
       ]},
      {"Keys for this screen",
       [
         "Tab moves between channel rows and required binding fields.",
         "Space toggles the focused channel when the cursor is on a channel row.",
         "When a binding field is focused, typing edits that field. The letter r is treated as text while a binding field is focused.",
         "When a channel row is focused, r refreshes connector auth from the server. Enter validates bindings and auth, then submits the publish request. Esc returns to the room."
       ]},
      {"Workflow",
       [
         "Use the readiness pane to clear blockers first, then select channels, fill every required binding, confirm auth shows connected, and press Enter.",
         "If auth is missing, complete connector setup outside the TUI, return here, and refresh auth before publishing."
       ]},
      {"Global", global_help_lines()}
    ])
  end

  defp wizard_lines(state) do
    render_sections([
      {"What this screen does",
       [
         "Create and start a new room in a short guided flow."
       ]},
      {"Current state",
       [
         "Step: #{wizard_step_label(state.wizard_step)}.",
         "Brief length: #{String.length(Map.get(state.wizard_fields, "brief", ""))} characters.",
         "Selected workers: #{length(Map.get(state.wizard_fields, "participants", []))}.",
         "Pending create: #{pending_room_label(state)}."
       ]},
      {"Keys for this step", wizard_step_keys(state)},
      {"Workflow",
       [
         "Step 0 defines the room objective. Step 1 chooses the dispatch policy. Step 2 reviews phases. Step 3 selects workers. Step 4 creates and runs the room.",
         "If worker or policy lists are empty, fix the server or local worker registration first; the wizard cannot create a useful room without them."
       ]},
      {"Global", global_help_lines()}
    ])
  end

  defp render_sections(sections) do
    sections
    |> Enum.map(fn {title, entries} ->
      [String.upcase(title) | Enum.map(entries, &("  - " <> &1))]
    end)
    |> Enum.intersperse([""])
    |> List.flatten()
  end

  defp global_help_lines do
    [
      "Ctrl+G or F1 opens help. F2 opens debug. Ctrl+C clears the active draft when you are typing; with no active draft it exits. Ctrl+Q always quits."
    ]
  end

  defp highlighted_room_label(state) do
    case Model.selected_lobby_room(state) do
      nil -> "none"
      %{room_id: room_id, fetch_error: true} -> "#{room_id} (stale local entry)"
      %{room_id: room_id} -> room_id
    end
  end

  defp selected_context_label(state) do
    case Model.selected_context(state) do
      nil -> "none"
      object -> context_id(object)
    end
  end

  defp room_stage_label(state) do
    state.snapshot
    |> Projection.workflow_summary()
    |> Map.fetch!(:stage)
  end

  defp draft_summary(%{pending_room_submit: %{text: text}}) when is_binary(text) do
    "#{String.length(text)} chars are being submitted."
  end

  defp draft_summary(state) do
    trimmed = String.trim(state.input_buffer)

    if trimmed == "" do
      "empty."
    else
      "#{String.length(state.input_buffer)} chars ready to send."
    end
  end

  defp room_enter_summary(%{pending_room_submit: pending}) when not is_nil(pending) do
    "wait for the current chat submission to finish."
  end

  defp room_enter_summary(state) do
    cond do
      String.trim(state.input_buffer) != "" ->
        "send the current draft as a contribution."

      selected_conflict?(state) ->
        "open conflict resolution for the selected contradiction."

      true ->
        "do nothing until you type a draft or select a contradiction."
    end
  end

  defp selected_conflict?(state) do
    case Model.selected_context(state) do
      nil -> false
      object -> Projection.conflict?(object, state.snapshot)
    end
  end

  defp publish_focus_label(state) do
    case Publish.current_focus(state) do
      %{type: :channel, channel: channel} -> "channel #{channel}"
      %{type: :binding, channel: channel, field: field} -> "binding #{channel}.#{field}"
      _other -> "none"
    end
  end

  defp selected_channels(state) do
    case state.publish_selected do
      [] -> "none"
      channels -> Enum.join(channels, ", ")
    end
  end

  defp publish_auth_summary(state) do
    channels =
      case state.publish_selected do
        [] ->
          state.publish_plan
          |> publication_entries()
          |> Enum.map(&(&1["channel"] || &1[:channel]))

        selected ->
          selected
      end

    case channels do
      [] ->
        "no channels loaded yet."

      _ ->
        channels
        |> Enum.map_join(", ", fn channel ->
          "#{channel}=#{publish_auth_status(state, channel)}"
        end)
    end
  end

  defp publish_ready_label(state) do
    status = Map.get(state.snapshot, "status") || Map.get(state.snapshot, :status)
    if status == "publication_ready", do: "yes", else: "no"
  end

  defp publish_auth_status(state, channel) do
    case Map.get(state.publish_auth_state, channel) do
      %{status: :cached} ->
        "connected"

      %{status: :pending, state: auth_state} when is_binary(auth_state) and auth_state != "" ->
        auth_state

      _other ->
        "missing"
    end
  end

  defp publication_entries(%{"publications" => publications}) when is_list(publications),
    do: publications

  defp publication_entries(%{"data" => %{"publications" => publications}})
       when is_list(publications),
       do: publications

  defp publication_entries(_other), do: []

  defp wizard_step_keys(%{wizard_step: 0}) do
    [
      "Type the room brief directly into the input box.",
      "Enter continues once the brief is long enough. Esc cancels back to the lobby."
    ]
  end

  defp wizard_step_keys(%{wizard_step: 1}) do
    [
      "Up/Down moves through dispatch policies.",
      "Enter chooses the highlighted policy. Esc returns to the brief."
    ]
  end

  defp wizard_step_keys(%{wizard_step: 2}) do
    [
      "This step is read-only.",
      "Enter continues to worker selection. Esc returns to policy selection."
    ]
  end

  defp wizard_step_keys(%{wizard_step: 3}) do
    [
      "Up/Down moves through worker targets. Space toggles the highlighted worker.",
      "Enter continues once at least one worker is selected. Esc returns to phases."
    ]
  end

  defp wizard_step_keys(%{wizard_step: 4, pending_room_create: pending})
       when not is_nil(pending) do
    [
      "Room creation is already running in the background.",
      "Wait for the room to open automatically, or use F2 for debug details if something looks stuck."
    ]
  end

  defp wizard_step_keys(%{wizard_step: 4}) do
    [
      "Review the plan carefully.",
      "Enter creates the room and starts the run. Esc returns to worker selection."
    ]
  end

  defp wizard_step_keys(_state) do
    ["Enter continues. Esc goes back one step."]
  end

  defp wizard_step_label(0), do: "0/4 — Brief"
  defp wizard_step_label(1), do: "1/4 — Dispatch Policy"
  defp wizard_step_label(2), do: "2/4 — Phases"
  defp wizard_step_label(3), do: "3/4 — Select Workers"
  defp wizard_step_label(4), do: "4/4 — Confirm"
  defp wizard_step_label(step), do: "#{step}/4"

  defp pending_room_label(%{pending_room_create: %{room_id: room_id}}), do: room_id
  defp pending_room_label(_state), do: "none"

  defp context_id(nil), do: "none"

  defp context_id(object),
    do: Map.get(object, "context_id") || Map.get(object, :context_id) || "none"
end
