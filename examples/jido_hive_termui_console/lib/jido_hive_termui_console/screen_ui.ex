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
  def help_popup_widgets(frame, %Model{help_visible: true}, title, lines) do
    area = root_area(frame)
    width = min(max(frame.width - 4, 40), 96)
    height = min(max(length(lines) + 5, 12), max(frame.height - 4, 10))

    content =
      text_widget(
        Enum.join(
          lines ++ ["", "Enter or Esc closes this guide. Ctrl+G or F1 opens it again."],
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
end
