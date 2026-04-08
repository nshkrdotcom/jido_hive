defmodule JidoHiveTermuiConsole.Screens.Wizard do
  @moduledoc false

  import TermUI.Component.Helpers

  alias JidoHiveTermuiConsole.Model
  alias TermUI.Event
  alias TermUI.Renderer.Style

  @spec event_to_msg(Event.t(), Model.t()) :: term() | nil
  def event_to_msg(%Event.Key{key: :up}, _state), do: :wizard_prev_option
  def event_to_msg(%Event.Key{key: :down}, _state), do: :wizard_next_option
  def event_to_msg(%Event.Key{key: :enter}, _state), do: :wizard_enter
  def event_to_msg(%Event.Key{key: :backspace}, _state), do: :wizard_backspace
  def event_to_msg(%Event.Key{key: :escape}, _state), do: :wizard_escape

  def event_to_msg(%Event.Key{char: "q", modifiers: modifiers}, _state) when is_list(modifiers) do
    if Enum.member?(modifiers, :ctrl), do: :quit, else: nil
  end

  def event_to_msg(%Event.Key{char: " "}, %{wizard_step: 3}), do: :wizard_toggle_worker

  def event_to_msg(%Event.Key{char: char}, %{wizard_step: 0})
      when is_binary(char) and char != "" do
    {:wizard_append, char}
  end

  def event_to_msg(_event, _state), do: nil

  @spec render(Model.t()) :: term()
  def render(%Model{} = state) do
    width = max(state.screen_width - 2, 48)

    stack(:vertical, [
      text(title_for_step(state), header_style()),
      box(Enum.map(step_lines(state), &text/1), width: width, height: 18),
      text(help_line(state), meta_style()),
      text(state.status_line, status_style(state))
    ])
  end

  @spec room_payload(Model.t()) :: map()
  def room_payload(%Model{} = state) do
    brief = Map.fetch!(state.wizard_fields, "brief")
    participants = Map.get(state.wizard_fields, "participants", [])

    %{
      "room_id" => generate_room_id(brief),
      "brief" => brief,
      "dispatch_policy_id" => Map.get(state.wizard_fields, "dispatch_policy_id"),
      "dispatch_policy_config" => %{"phases" => Map.get(state.wizard_fields, "phases", [])},
      "participants" =>
        Enum.map(participants, fn target ->
          %{
            "participant_id" => target["participant_id"],
            "participant_role" => "worker",
            "participant_kind" => "runtime",
            "target_id" => target["target_id"],
            "capability_id" => target["capability_id"]
          }
        end)
    }
  end

  defp title_for_step(%{wizard_step: 0}), do: "NEW ROOM — Step 0 of 4: Brief"
  defp title_for_step(%{wizard_step: 1}), do: "NEW ROOM — Step 1 of 4: Dispatch Policy"
  defp title_for_step(%{wizard_step: 2}), do: "NEW ROOM — Step 2 of 4: Phases"
  defp title_for_step(%{wizard_step: 3}), do: "NEW ROOM — Step 3 of 4: Select Workers"
  defp title_for_step(%{wizard_step: 4}), do: "NEW ROOM — Step 4 of 4: Confirm"

  defp step_lines(%{wizard_step: 0} = state) do
    [
      "Enter Room Objective:",
      "> " <> Map.get(state.wizard_fields, "brief", "")
    ]
  end

  defp step_lines(%{wizard_step: 1, wizard_available_policies: []}), do: ["Loading policies..."]

  defp step_lines(%{wizard_step: 1} = state) do
    Enum.with_index(state.wizard_available_policies)
    |> Enum.map(&policy_line(&1, state.wizard_cursor))
  end

  defp step_lines(%{wizard_step: 2} = state) do
    phases = Map.get(state.wizard_fields, "phases", [])

    ["Phases from selected policy:"]
    |> Kernel.++(phase_lines(phases))
    |> Kernel.++(["", "Enter to continue."])
  end

  defp step_lines(%{wizard_step: 3, wizard_available_targets: []}), do: ["Loading targets..."]

  defp step_lines(%{wizard_step: 3} = state) do
    selected = Map.get(state.wizard_fields, "participants", [])

    target_lines =
      Enum.with_index(state.wizard_available_targets)
      |> Enum.map(&worker_line(&1, state.wizard_cursor, selected))

    target_lines ++ ["", "Selected: #{length(selected)}"]
  end

  defp step_lines(%{wizard_step: 4} = state) do
    participants = Map.get(state.wizard_fields, "participants", [])
    phases = Map.get(state.wizard_fields, "phases", [])

    [
      "Brief: #{Map.get(state.wizard_fields, "brief", "")}",
      "Policy: #{Map.get(state.wizard_fields, "dispatch_policy_id", "")}",
      "Phases: #{phase_summary(phases)}",
      "Workers: #{Enum.map_join(participants, ", ", & &1["participant_id"])}",
      "",
      "Enter to create and run the room."
    ]
  end

  defp help_line(%{wizard_step: 0}), do: "Type brief  ·  Enter next  ·  ESC cancel"
  defp help_line(%{wizard_step: 3}), do: "Space toggle  ·  ↑↓ move  ·  Enter next  ·  ESC back"
  defp help_line(_state), do: "↑↓ move  ·  Enter next  ·  ESC back"

  defp generate_room_id(brief) do
    slug =
      brief
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> String.slice(0, 24)

    suffix =
      2
      |> :crypto.strong_rand_bytes()
      |> Base.encode16(case: :lower)

    "#{slug}-#{suffix}"
  end

  defp same_target?(left, right) do
    (left["target_id"] || left[:target_id]) == (right["target_id"] || right[:target_id])
  end

  defp policy_line({policy, index}, cursor) do
    prefix = if index == cursor, do: ">", else: " "
    "#{prefix} #{policy["policy_id"]} — #{policy["display_name"]} — #{policy["description"]}"
  end

  defp worker_line({target, index}, cursor, selected) do
    marker = if Enum.any?(selected, &same_target?(&1, target)), do: "[x]", else: "[ ]"
    prefix = if index == cursor, do: ">", else: " "

    "#{prefix} #{marker}  #{target["participant_id"]}  #{target["participant_role"]}  #{target["provider"]}  #{target["capability_id"]}"
  end

  defp phase_lines([]), do: ["[no phases]"]

  defp phase_lines(phases) when is_list(phases) do
    phases
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {phase, index} -> render_phase(index, phase) end)
  end

  defp phase_summary([]), do: "[no phases]"

  defp phase_summary(phases) when is_list(phases) do
    Enum.map_join(phases, ", ", &phase_label/1)
  end

  defp render_phase(index, phase) do
    heading = "#{index}. #{phase_label(phase)}"

    case phase_objective(phase) do
      nil -> [heading]
      objective -> [heading, "   #{objective}"]
    end
  end

  defp phase_label(%{} = phase) do
    phase["phase"] || phase[:phase] || phase["objective"] || phase[:objective] ||
      "[unnamed phase]"
  end

  defp phase_label(phase) when is_binary(phase), do: phase
  defp phase_label(phase), do: inspect(phase)

  defp phase_objective(%{} = phase) do
    phase["objective"] || phase[:objective]
  end

  defp phase_objective(_phase), do: nil

  defp header_style, do: Style.new(fg: :cyan, attrs: [:bold])
  defp meta_style, do: Style.new(fg: :bright_black)
  defp status_style(%{status_severity: :error}), do: Style.new(fg: :red, attrs: [:bold])
  defp status_style(%{status_severity: :warn}), do: Style.new(fg: :yellow)
  defp status_style(_state), do: Style.new(fg: :yellow)
end
