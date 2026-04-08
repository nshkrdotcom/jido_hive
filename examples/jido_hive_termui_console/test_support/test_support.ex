defmodule JidoHiveTermuiConsole.TestSupport do
  alias TermUI.Component.RenderNode

  def tmp_dir do
    path =
      Path.join(
        System.tmp_dir!(),
        "jido_hive_termui_console_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  def collect_text(%RenderNode{type: :text, content: content}), do: [content]
  def collect_text(%RenderNode{children: children}), do: Enum.flat_map(children, &collect_text/1)
  def collect_text(list) when is_list(list), do: Enum.flat_map(list, &collect_text/1)
  def collect_text(_other), do: []
end
