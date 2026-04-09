defmodule JidoHiveTermuiConsole.ScreenUI do
  @moduledoc false

  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, Paragraph, Popup}
  alias JidoHiveTermuiConsole.Model

  @spec root_area(%{width: pos_integer(), height: pos_integer()}) :: Rect.t()
  def root_area(%{width: width, height: height}) do
    %Rect{x: 0, y: 0, width: width, height: height}
  end

  @spec pane(String.t(), [String.t()] | String.t(), keyword()) :: Paragraph.t()
  def pane(title, lines, opts \\ []) do
    %Paragraph{
      text: to_text(lines),
      wrap: Keyword.get(opts, :wrap, true),
      scroll: Keyword.get(opts, :scroll, {0, 0}),
      style: Keyword.get(opts, :style, %Style{fg: :white}),
      block: panel_block(title, opts)
    }
  end

  @spec text_widget(String.t(), keyword()) :: Paragraph.t()
  def text_widget(text, opts \\ []) do
    %Paragraph{
      text: text,
      wrap: Keyword.get(opts, :wrap, true),
      alignment: Keyword.get(opts, :alignment, :left),
      style: Keyword.get(opts, :style, %Style{fg: :white}),
      block: Keyword.get(opts, :block)
    }
  end

  @spec help_popup_widgets(
          %{width: pos_integer(), height: pos_integer()},
          Model.t(),
          String.t(),
          [String.t()]
        ) ::
          [{Popup.t(), Rect.t()}]
  def help_popup_widgets(frame, %Model{debug_visible: true} = state, _title, _lines) do
    area = root_area(frame)
    width = min(max(frame.width - 4, 60), 110)
    height = min(max(length(debug_lines(state)) + 5, 14), max(frame.height - 4, 12))

    popup = %Popup{
      content:
        text_widget(Enum.join(debug_lines(state), "\n"), style: %Style{fg: :white}, wrap: true),
      block: %Block{
        title: "Debug",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :cyan},
        padding: {1, 1, 1, 1}
      },
      fixed_width: width,
      fixed_height: height
    }

    [{popup, area}]
  end

  def help_popup_widgets(frame, %Model{help_visible: true}, title, lines) do
    area = root_area(frame)
    available_width = max(frame.width - 4, 20)
    width = available_width |> min(124) |> max(min(56, available_width))
    available_height = max(frame.height - 4, 10)
    height = min(max(length(lines) + 6, 16), available_height)

    content =
      text_widget(
        Enum.join(
          lines ++
            [
              "",
              "Enter or Esc closes this help. Ctrl+G or F1 opens it again. F2 shows debug."
            ],
          "\n"
        ),
        style: %Style{fg: :white},
        wrap: true
      )

    popup = %Popup{
      content: content,
      block: %Block{
        title: title,
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :yellow},
        padding: {1, 1, 1, 1}
      },
      fixed_width: width,
      fixed_height: height
    }

    [{popup, area}]
  end

  def help_popup_widgets(_frame, _state, _title, _lines), do: []

  @spec header_style() :: Style.t()
  def header_style, do: %Style{fg: :cyan, modifiers: [:bold]}

  @spec meta_style() :: Style.t()
  def meta_style, do: %Style{fg: :dark_gray}

  @spec accent_style() :: Style.t()
  def accent_style, do: %Style{fg: :yellow, modifiers: [:bold]}

  @spec status_style(Model.t()) :: Style.t()
  def status_style(%{status_severity: :error}), do: %Style{fg: :red, modifiers: [:bold]}
  def status_style(%{status_severity: :warn}), do: %Style{fg: :yellow}
  def status_style(_state), do: %Style{fg: :green}

  defp panel_block(title, opts) do
    %Block{
      title: title,
      borders: Keyword.get(opts, :borders, [:all]),
      border_type: Keyword.get(opts, :border_type, :rounded),
      border_style:
        Keyword.get(opts, :border_style, %Style{fg: Keyword.get(opts, :border_fg, :cyan)}),
      padding: Keyword.get(opts, :padding, {1, 1, 0, 0})
    }
  end

  defp to_text(lines) when is_list(lines), do: Enum.join(lines, "\n")
  defp to_text(text) when is_binary(text), do: text

  defp debug_lines(state) do
    pending_room =
      case state.pending_room_create do
        %{room_id: room_id} -> room_id
        _other -> "none"
      end

    pending_submit =
      case state.pending_room_submit do
        %{room_id: room_id, text: text} -> "#{room_id} (#{String.length(text)} chars)"
        _other -> "none"
      end

    [
      "Screen: #{state.active_screen}",
      "Room: #{state.room_id || "none"}",
      "Wizard step: #{state.wizard_step}",
      "Participant: #{state.participant_id} / #{state.participant_role} / #{state.authority_level}",
      "API: #{state.api_base_url}",
      "Status: [#{state.status_severity}] #{state.status_line}",
      "Pending room create: #{pending_room}",
      "Pending room submit: #{pending_submit}",
      "Poll interval: #{state.poll_interval_ms}ms",
      "",
      "F2, Enter, or Esc closes this view.",
      "Ctrl+C or Ctrl+Q exits the console.",
      "For file logging, rerun with --debug and inspect ~/.config/hive/termui_console.log.",
      "If the terminal is ever left dirty after a crash, run: reset"
    ]
  end
end
