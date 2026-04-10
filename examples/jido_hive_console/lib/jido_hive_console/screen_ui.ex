defmodule JidoHiveConsole.ScreenUI do
  @moduledoc false

  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, Paragraph, Popup}
  alias JidoHiveConsole.Model

  @pending_indicator_width 16
  @pending_indicator_domain 3.0
  @pending_indicator_pass_ms 1_000
  @pending_indicator_tick_ms 125

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

  def status_style(%{pending_room_submit: pending}) when not is_nil(pending),
    do: %Style{fg: :cyan, modifiers: [:bold]}

  def status_style(_state), do: %Style{fg: :green}

  @spec status_text(Model.t()) :: String.t()
  def status_text(%Model{} = state), do: status_text(state, animation_time_ms(state))

  @spec status_text(Model.t(), integer() | nil) :: String.t()
  def status_text(%Model{pending_room_submit: pending} = state, now_ms)
      when not is_nil(pending) do
    "#{state.status_line}  #{pending_indicator(now_ms)}"
  end

  def status_text(%Model{} = state, _now_ms), do: state.status_line

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

  defp pending_indicator(now_ms) do
    center = shimmer_center(now_ms)

    bar =
      0..(@pending_indicator_width - 1)
      |> Enum.map_join(&indicator_glyph(indicator_weight(&1, center)))

    "[" <> bar <> "]"
  end

  defp animation_time_ms(%Model{status_animation_tick: tick})
       when is_integer(tick) and tick >= 0 do
    tick * @pending_indicator_tick_ms
  end

  defp animation_time_ms(_state), do: 0

  defp shimmer_center(nil), do: shimmer_center(System.monotonic_time(:millisecond))

  defp shimmer_center(now_ms) when is_integer(now_ms) do
    phase = rem(now_ms, @pending_indicator_pass_ms) / @pending_indicator_pass_ms
    phase * max(@pending_indicator_width - 1, 1)
  end

  defp indicator_weight(index, center) do
    distance = abs(index - center)
    x = min(distance / @pending_indicator_domain, 1.0)
    max(0.0, 1.0 - :math.pow(x, 3))
  end

  defp indicator_glyph(weight) when weight >= 0.9, do: "█"
  defp indicator_glyph(weight) when weight >= 0.72, do: "▓"
  defp indicator_glyph(weight) when weight >= 0.52, do: "▒"
  defp indicator_glyph(weight) when weight >= 0.28, do: "░"
  defp indicator_glyph(_weight), do: " "

  defp debug_lines(state) do
    [
      "Screen: #{state.active_screen}",
      "Room: #{state.room_id || "none"}",
      "Wizard step: #{state.wizard_step}",
      "Participant: #{state.participant_id} / #{state.participant_role} / #{state.authority_level}",
      "API: #{state.api_base_url}",
      "Status: [#{state.status_severity}] #{status_text(state, 0)}",
      "Pending room create: #{pending_room_create_line(state)}",
      "Pending room submit: #{pending_room_submit_line(state)}",
      "Pending room run: #{pending_room_run_line(state)}",
      "Poll interval: #{state.poll_interval_ms}ms",
      latest_operation_line(state)
    ] ++
      runtime_debug_lines(state) ++
      transport_debug_lines(state) ++
      [
        "",
        "F2, Enter, or Esc closes this view.",
        "Ctrl+C or Ctrl+Q exits the console.",
        "For file logging, rerun with --debug and inspect ~/.config/hive/hive_console.log.",
        "If the terminal is ever left dirty after a crash, run: reset"
      ]
  end

  defp pending_room_create_line(state) do
    case state.pending_room_create do
      %{room_id: room_id} -> room_id
      _other -> "none"
    end
  end

  defp pending_room_submit_line(state) do
    case state.pending_room_submit do
      %{room_id: room_id, text: text, operation_id: operation_id} ->
        "#{room_id} op=#{operation_id} (#{String.length(text)} chars)"

      _other ->
        "none"
    end
  end

  defp pending_room_run_line(state) do
    case state.pending_room_run do
      %{room_id: room_id, operation_id: operation_id} -> "#{room_id} op=#{operation_id}"
      _other -> "none"
    end
  end

  defp latest_operation_line(state) do
    case state.snapshot |> Map.get("operations", []) |> List.first() do
      %{"operation_id" => operation_id, "status" => status} ->
        "Latest operation: #{operation_id} status=#{status}"

      _other ->
        "Latest operation: none"
    end
  end

  defp runtime_debug_lines(%{runtime_snapshot: nil}) do
    ["Runtime: pending snapshot"]
  end

  defp runtime_debug_lines(%{runtime_snapshot: snapshot}) when is_map(snapshot) do
    [
      "Runtime: mode=#{runtime_snapshot_value(snapshot, :mode)} renders=#{runtime_snapshot_value(snapshot, :render_count)} async=#{runtime_snapshot_value(snapshot, :active_async_commands)}",
      "Runtime trace: enabled=#{runtime_snapshot_value(snapshot, :trace_enabled?)} events=#{length(runtime_snapshot_value(snapshot, :trace_events, []))}",
      "Runtime subscriptions: #{runtime_snapshot_value(snapshot, :subscription_count, 0)}"
    ] ++
      runtime_subscription_lines(snapshot) ++
      runtime_trace_lines(snapshot)
  end

  defp runtime_debug_lines(_state), do: ["Runtime: unavailable"]

  defp runtime_subscription_lines(snapshot) do
    snapshot
    |> runtime_snapshot_value(:subscriptions, [])
    |> Enum.take(3)
    |> Enum.map(fn subscription ->
      id = runtime_snapshot_value(subscription, :id)
      kind = runtime_snapshot_value(subscription, :kind)
      interval_ms = runtime_snapshot_value(subscription, :interval_ms)
      active? = runtime_snapshot_value(subscription, :active?)
      "sub #{id}: #{kind} #{interval_ms}ms active=#{active?}"
    end)
  end

  defp runtime_trace_lines(snapshot) do
    snapshot
    |> runtime_snapshot_value(:trace_events, [])
    |> Enum.take(3)
    |> Enum.map(fn event ->
      kind = runtime_snapshot_value(event, :kind)
      details = runtime_snapshot_value(event, :details, %{})
      "trace #{kind}: #{runtime_trace_summary(details)}"
    end)
  end

  defp runtime_trace_summary(details) when is_map(details) do
    cond do
      Map.has_key?(details, :id) or Map.has_key?(details, "id") ->
        "id=#{runtime_snapshot_value(details, :id)}"

      Map.has_key?(details, :kind) or Map.has_key?(details, "kind") ->
        "kind=#{runtime_snapshot_value(details, :kind)}"

      Map.has_key?(details, :source) or Map.has_key?(details, "source") ->
        "source=#{runtime_snapshot_value(details, :source)}"

      true ->
        inspect(details)
    end
  end

  defp runtime_trace_summary(other), do: inspect(other)

  defp runtime_snapshot_value(map, key, default \\ nil)

  defp runtime_snapshot_value(map, key, default) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, to_string(key), default)
    end
  end

  defp runtime_snapshot_value(_other, _key, default), do: default

  defp transport_debug_lines(state) do
    state.snapshot
    |> Map.get("transport", %{})
    |> Map.get("lanes", [])
    |> Enum.map(fn lane ->
      "#{lane["lane"]}: active=#{lane["active_requests"]} completed=#{lane["completed_requests"]} failed=#{lane["failed_requests"]} timeouts=#{lane["timeout_count"]}"
    end)
    |> Enum.take(4)
  end
end
