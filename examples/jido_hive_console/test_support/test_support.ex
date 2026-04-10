defmodule JidoHiveConsole.TestSupport do
  alias ExRatatui
  alias ExRatatui.Widgets.{List, Paragraph, Popup, TextInput}

  def tmp_dir do
    path =
      Path.join(
        System.tmp_dir!(),
        "jido_hive_console_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  def collect_text(rendered) do
    rendered
    |> do_collect_text()
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  def widgets(rendered, module), do: do_widgets(rendered, module)

  def text_input_values(rendered) do
    widgets(rendered, TextInput)
    |> Enum.map(&text_input_value/1)
  end

  defp do_collect_text({widget, _area}), do: do_collect_text(widget)

  defp do_collect_text(%Paragraph{text: text, block: block}) do
    [block_title(block), text]
  end

  defp do_collect_text(%List{items: items, block: block}) do
    [block_title(block) | items]
  end

  defp do_collect_text(%Popup{content: content, block: block}) do
    [block_title(block) | do_collect_text(content)]
  end

  defp do_collect_text(%TextInput{state: state, placeholder: placeholder, block: block}) do
    value = text_input_value(%TextInput{state: state, placeholder: placeholder})
    [block_title(block), value]
  end

  defp do_collect_text(list) when is_list(list), do: Enum.flat_map(list, &do_collect_text/1)
  defp do_collect_text(_other), do: []

  defp do_widgets({widget, _area}, module), do: do_widgets(widget, module)

  defp do_widgets(%Popup{content: content} = widget, module) do
    maybe_widget(widget, module) ++ do_widgets(content, module)
  end

  defp do_widgets(widgets, module) when is_list(widgets) do
    Enum.flat_map(widgets, &do_widgets(&1, module))
  end

  defp do_widgets(widget, module) when is_map(widget) do
    maybe_widget(widget, module)
  end

  defp do_widgets(_other, _module), do: []

  defp maybe_widget(%{__struct__: module} = widget, module), do: [widget]
  defp maybe_widget(_widget, _module), do: []

  defp block_title(%{title: title}) when is_binary(title) and title != "", do: title
  defp block_title(_block), do: nil

  defp text_input_value(%TextInput{state: state, placeholder: placeholder}) when is_reference(state) do
    case ExRatatui.text_input_get_value(state) do
      "" -> placeholder
      value -> value
    end
  end

  defp text_input_value(%TextInput{placeholder: placeholder}), do: placeholder
end
