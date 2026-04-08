defmodule JidoHiveTermuiConsole.Screens.Wizard do
  @moduledoc false

  alias ExRatatui.Event
  alias ExRatatui.Layout
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{List, Paragraph, TextInput}
  alias JidoHiveTermuiConsole.{InputKey, Model, ScreenUI}

  @spec event_to_msg(Event.t(), Model.t()) :: term() | nil
  def event_to_msg(%Event.Key{code: "up"}, _state), do: :wizard_prev_option
  def event_to_msg(%Event.Key{code: "down"}, _state), do: :wizard_next_option
  def event_to_msg(%Event.Key{code: "enter"}, _state), do: :wizard_enter
  def event_to_msg(%Event.Key{code: "esc"}, _state), do: :wizard_escape
  def event_to_msg(%Event.Key{code: "q", modifiers: ["ctrl"]}, _state), do: :quit

  def event_to_msg(%Event.Key{code: " ", modifiers: []}, %{wizard_step: 3}),
    do: :wizard_toggle_worker

  def event_to_msg(%Event.Key{} = event, %{wizard_step: 0}) do
    case InputKey.text_input_key(event) do
      {:ok, code} -> {:wizard_input_key, code}
      :error -> nil
    end
  end

  def event_to_msg(_event, _state), do: nil

  @spec render(Model.t(), %{width: pos_integer(), height: pos_integer()}) :: [{term(), term()}]
  def render(%Model{} = state, frame) do
    area = ScreenUI.root_area(frame)

    [header_area, body_area, footer_area, status_area] =
      Layout.split(area, :vertical, [{:length, 2}, {:min, 10}, {:length, 2}, {:length, 1}])

    widgets = [
      {header_widget(state), header_area},
      {body_widget(state), body_area},
      {footer_widget(state), footer_area},
      {status_widget(state), status_area}
    ]

    widgets ++ ScreenUI.help_popup_widgets(frame, state, "Wizard Guide", guide_lines(state))
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

  defp header_widget(state) do
    %Paragraph{
      text: title_for_step(state),
      wrap: false,
      style: ScreenUI.header_style(),
      block: %ExRatatui.Widgets.Block{
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan},
        padding: {1, 1, 0, 0}
      }
    }
  end

  defp body_widget(%Model{wizard_step: 0, wizard_brief_input_ref: ref}) when is_reference(ref) do
    %TextInput{
      state: ref,
      style: %Style{fg: :white},
      cursor_style: %Style{fg: :black, bg: :white},
      placeholder: "Describe the room objective...",
      placeholder_style: ScreenUI.meta_style(),
      block: %ExRatatui.Widgets.Block{
        title: "Room Brief",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :yellow},
        padding: {1, 1, 0, 0}
      }
    }
  end

  defp body_widget(%Model{wizard_step: 0} = state) do
    ScreenUI.pane("Room Brief", ["> " <> Map.get(state.wizard_fields, "brief", "")],
      border_fg: :yellow,
      wrap: true
    )
  end

  defp body_widget(%Model{wizard_step: 1, wizard_policies_state: status})
       when status in [:idle, :loading] do
    ScreenUI.pane("Dispatch Policy", ["Loading policies..."], border_fg: :cyan)
  end

  defp body_widget(%Model{wizard_step: 1, wizard_policies_state: :error}) do
    ScreenUI.pane(
      "Dispatch Policy",
      ["Policy list could not be loaded.", "", "Check the status line or rerun with --debug."],
      border_fg: :red
    )
  end

  defp body_widget(%Model{wizard_step: 1, wizard_available_policies: []}) do
    ScreenUI.pane(
      "Dispatch Policy",
      [
        "No policies available on this server.",
        "",
        "Room creation requires at least one dispatch policy."
      ],
      border_fg: :yellow
    )
  end

  defp body_widget(%Model{wizard_step: 1} = state) do
    %List{
      items:
        Enum.with_index(state.wizard_available_policies)
        |> Enum.map(fn {policy, _index} -> policy_line(policy) end),
      selected: state.wizard_cursor,
      highlight_symbol: "> ",
      style: %Style{fg: :white},
      highlight_style: %Style{fg: :yellow, modifiers: [:bold]},
      block: %ExRatatui.Widgets.Block{
        title: "Dispatch Policy",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan},
        padding: {1, 1, 0, 0}
      }
    }
  end

  defp body_widget(%Model{wizard_step: 2} = state) do
    ScreenUI.pane(
      "Selected Phases",
      ["Phases from selected policy:"] ++
        phase_lines(Map.get(state.wizard_fields, "phases", [])) ++ ["", "Enter to continue."],
      border_fg: :green,
      wrap: true
    )
  end

  defp body_widget(%Model{wizard_step: 3, wizard_targets_state: status})
       when status in [:idle, :loading] do
    ScreenUI.pane("Select Workers", ["Loading targets..."], border_fg: :cyan)
  end

  defp body_widget(%Model{wizard_step: 3, wizard_targets_state: :error}) do
    ScreenUI.pane(
      "Select Workers",
      ["Worker targets could not be loaded.", "", "Check the status line or rerun with --debug."],
      border_fg: :red
    )
  end

  defp body_widget(%Model{wizard_step: 3, wizard_available_targets: []}) do
    ScreenUI.pane(
      "Select Workers",
      [
        "No worker targets available on this server.",
        "",
        "Room creation requires at least one registered worker target.",
        "Start local workers with bin/hive-clients, then refresh and continue."
      ],
      border_fg: :yellow
    )
  end

  defp body_widget(%Model{wizard_step: 3} = state) do
    selected = Map.get(state.wizard_fields, "participants", [])

    %List{
      items: Enum.map(state.wizard_available_targets, &worker_line(&1, selected)),
      selected: state.wizard_cursor,
      highlight_symbol: "> ",
      style: %Style{fg: :white},
      highlight_style: %Style{fg: :yellow, modifiers: [:bold]},
      block: %ExRatatui.Widgets.Block{
        title: "Select Workers",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan},
        padding: {1, 1, 0, 0}
      }
    }
  end

  defp body_widget(%Model{wizard_step: 4} = state) do
    participants = Map.get(state.wizard_fields, "participants", [])
    phases = Map.get(state.wizard_fields, "phases", [])

    ScreenUI.pane(
      "Confirm",
      [
        "Brief: #{Map.get(state.wizard_fields, "brief", "")}",
        "Policy: #{Map.get(state.wizard_fields, "dispatch_policy_id", "")}",
        "Phases: #{phase_summary(phases)}",
        "Workers: #{Enum.map_join(participants, ", ", & &1["participant_id"])}",
        "",
        "Enter to create and run the room."
      ],
      border_fg: :green,
      wrap: true
    )
  end

  defp footer_widget(state) do
    ScreenUI.text_widget(Enum.join(help_lines(state), "  ·  "),
      style: ScreenUI.meta_style(),
      wrap: true
    )
  end

  defp status_widget(state) do
    ScreenUI.text_widget(state.status_line, style: ScreenUI.status_style(state), wrap: false)
  end

  defp help_lines(%{wizard_step: 0}),
    do: ["Type brief", "Enter continue", "Esc cancel", "Ctrl+Q quit"]

  defp help_lines(%{wizard_step: 3}),
    do: ["Up/Down move", "Space toggle worker", "Enter continue", "Esc back", "Ctrl+Q quit"]

  defp help_lines(%{wizard_step: 4}),
    do: ["Review plan", "Enter create room", "Esc back", "Ctrl+Q quit"]

  defp help_lines(_state), do: ["Up/Down move", "Enter continue", "Esc back", "Ctrl+Q quit"]

  defp guide_lines(%{wizard_step: 0}) do
    [
      "Step 0 collects the room brief.",
      "Type a concrete objective. The brief must be at least 10 characters long.",
      "Press Enter to continue once the brief is ready."
    ]
  end

  defp guide_lines(%{wizard_step: 1}) do
    [
      "Step 1 selects the dispatch policy.",
      "Use Up and Down to move through policies.",
      "Press Enter to choose the highlighted policy."
    ]
  end

  defp guide_lines(%{wizard_step: 2}) do
    [
      "Step 2 reviews the phases that came from the selected policy.",
      "This step is read-only.",
      "Press Enter to continue to worker selection."
    ]
  end

  defp guide_lines(%{wizard_step: 3}) do
    [
      "Step 3 chooses worker targets for the room.",
      "Use Up and Down to move through targets.",
      "Press Space to toggle the highlighted worker.",
      "Press Enter when you have selected at least one worker."
    ]
  end

  defp guide_lines(%{wizard_step: 4}) do
    [
      "Step 4 confirms the plan.",
      "Review the brief, policy, phases, and selected workers.",
      "Press Enter to create the room and start it in the background."
    ]
  end

  defp title_for_step(%{wizard_step: 0}), do: "NEW ROOM — Step 0 of 4: Brief"
  defp title_for_step(%{wizard_step: 1}), do: "NEW ROOM — Step 1 of 4: Dispatch Policy"
  defp title_for_step(%{wizard_step: 2}), do: "NEW ROOM — Step 2 of 4: Phases"
  defp title_for_step(%{wizard_step: 3}), do: "NEW ROOM — Step 3 of 4: Select Workers"
  defp title_for_step(%{wizard_step: 4}), do: "NEW ROOM — Step 4 of 4: Confirm"

  defp generate_room_id(brief) do
    slug =
      brief
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> String.slice(0, 24)

    suffix = 2 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
    "#{slug}-#{suffix}"
  end

  defp same_target?(left, right) do
    (left["target_id"] || left[:target_id]) == (right["target_id"] || right[:target_id])
  end

  defp policy_line(policy) do
    "#{policy["policy_id"]} — #{policy["display_name"]} — #{policy["description"]}"
  end

  defp worker_line(target, selected) do
    marker = if Enum.any?(selected, &same_target?(&1, target)), do: "[x]", else: "[ ]"

    "#{marker}  #{target["participant_id"]}  #{target["participant_role"]}  #{target["provider"]}  #{target["capability_id"]}"
  end

  defp phase_lines([]), do: ["[no phases]"]

  defp phase_lines(phases) when is_list(phases),
    do:
      phases
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {phase, index} -> render_phase(index, phase) end)

  defp phase_summary([]), do: "[no phases]"
  defp phase_summary(phases) when is_list(phases), do: Enum.map_join(phases, ", ", &phase_label/1)

  defp render_phase(index, phase) do
    heading = "#{index}. #{phase_label(phase)}"

    case phase_objective(phase) do
      nil -> [heading]
      objective -> [heading, "   #{objective}"]
    end
  end

  defp phase_label(%{} = phase),
    do:
      phase["phase"] || phase[:phase] || phase["objective"] || phase[:objective] ||
        "[unnamed phase]"

  defp phase_label(phase) when is_binary(phase), do: phase
  defp phase_label(phase), do: inspect(phase)

  defp phase_objective(%{} = phase), do: phase["objective"] || phase[:objective]
  defp phase_objective(_phase), do: nil
end
