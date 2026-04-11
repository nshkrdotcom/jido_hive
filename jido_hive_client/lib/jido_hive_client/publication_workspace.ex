defmodule JidoHiveClient.PublicationWorkspace do
  @moduledoc """
  Structured publication workspace data for headless and interactive clients.
  """

  @type t :: %{
          duplicate_policy: String.t() | nil,
          source_entries: [String.t()],
          channels: [map()],
          selected_channel: map() | nil,
          preview_lines: [String.t()],
          readiness: [String.t()],
          ready?: boolean()
        }

  @spec build(map(), map(), keyword()) :: t()
  def build(plan, auth_state, opts \\ [])

  def build(plan, auth_state, opts) when is_map(plan) and is_map(auth_state) do
    selected_channel_id = Keyword.get(opts, :selected_channel)
    channels = build_channels(plan, auth_state, selected_channel_id)
    selected_channel = Enum.find(channels, & &1.selected?)

    %{
      duplicate_policy: Map.get(plan, "duplicate_policy") || Map.get(plan, :duplicate_policy),
      source_entries: Map.get(plan, "source_entries") || Map.get(plan, :source_entries) || [],
      channels: channels,
      selected_channel: selected_channel,
      preview_lines: preview_lines(selected_channel),
      readiness: readiness_lines(channels, selected_channel),
      ready?: ready?(channels, selected_channel)
    }
  end

  def build(_plan, _auth_state, _opts) do
    build(%{}, %{})
  end

  defp build_channels(plan, auth_state, selected_channel_id) do
    publications = Map.get(plan, "publications") || Map.get(plan, :publications) || []
    selected_channel_id = selected_channel_id || publications |> List.first() |> channel_id()

    Enum.map(publications, fn publication ->
      channel = channel_id(publication)
      auth = Map.get(auth_state, channel, %{})

      required_bindings =
        Map.get(publication, "required_bindings") || Map.get(publication, :required_bindings) ||
          []

      %{
        channel: channel,
        selected?: channel == selected_channel_id,
        auth: %{
          status: Map.get(auth, :status, :missing),
          connection_id: Map.get(auth, :connection_id),
          state: Map.get(auth, :state),
          source: Map.get(auth, :source)
        },
        required_bindings: Enum.map(required_bindings, &normalize_binding/1),
        draft: Map.get(publication, "draft") || Map.get(publication, :draft) || %{}
      }
    end)
  end

  defp normalize_binding(binding) do
    %{
      field: Map.get(binding, "field") || Map.get(binding, :field),
      description: Map.get(binding, "description") || Map.get(binding, :description) || ""
    }
  end

  defp preview_lines(nil), do: ["No publication channel selected."]

  defp preview_lines(channel) do
    title = Map.get(channel.draft, "title") || Map.get(channel.draft, :title) || "Untitled"
    body = Map.get(channel.draft, "body") || Map.get(channel.draft, :body) || ""
    [title | String.split(body, "\n", trim: true)]
  end

  defp readiness_lines([], _selected_channel), do: ["Select at least one publication channel."]

  defp readiness_lines(channels, selected_channel) do
    selected_line =
      case selected_channel do
        nil -> "Select at least one publication channel."
        channel -> "Selected channel: #{channel.channel}"
      end

    auth_lines =
      Enum.map(channels, fn channel ->
        "#{channel.channel}: #{auth_label(channel.auth)}"
      end)

    [selected_line | auth_lines]
  end

  defp ready?([], _selected_channel), do: false

  defp ready?(channels, selected_channel) do
    not is_nil(selected_channel) and
      Enum.any?(channels, fn channel ->
        channel.selected? and channel.auth.status in [:cached, :connected]
      end)
  end

  defp auth_label(%{status: :cached, connection_id: connection_id})
       when is_binary(connection_id) and connection_id != "" do
    "connected (#{connection_id})"
  end

  defp auth_label(%{status: :connected}), do: "connected"
  defp auth_label(%{status: :pending, state: state}) when is_binary(state), do: state
  defp auth_label(_auth), do: "not configured"

  defp channel_id(publication) when is_map(publication) do
    Map.get(publication, "channel") || Map.get(publication, :channel)
  end

  defp channel_id(_publication), do: nil
end
