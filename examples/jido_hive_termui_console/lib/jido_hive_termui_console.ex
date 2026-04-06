defmodule JidoHiveTermuiConsole do
  @moduledoc false

  alias JidoHiveClient.Embedded
  alias TermUI.Runtime

  @spec run() :: no_return()
  @spec run(keyword()) :: no_return()
  def run(opts \\ []) do
    {embedded, owned_embedded?} = ensure_embedded(opts)

    runtime_opts = [
      root: JidoHiveTermuiConsole.App,
      embedded: embedded,
      embedded_module: Keyword.get(opts, :embedded_module, Embedded),
      room_id: Keyword.fetch!(opts, :room_id),
      participant_id: Keyword.get(opts, :participant_id, "human-local"),
      participant_role: Keyword.get(opts, :participant_role, "collaborator"),
      poll_interval_ms: Keyword.get(opts, :poll_interval_ms, 500)
    ]

    try do
      Runtime.run(runtime_opts)
    after
      if owned_embedded?, do: Embedded.shutdown(embedded)
    end
  end

  defp ensure_embedded(opts) do
    case Keyword.get(opts, :embedded) do
      nil ->
        embedded_opts = [
          room_id: Keyword.fetch!(opts, :room_id),
          api_base_url: Keyword.get(opts, :api_base_url, "http://127.0.0.1:4000/api"),
          participant_id: Keyword.get(opts, :participant_id, "human-local"),
          participant_role: Keyword.get(opts, :participant_role, "collaborator"),
          poll_interval_ms: Keyword.get(opts, :poll_interval_ms, 500)
        ]

        {:ok, embedded} = Embedded.start_link(embedded_opts)
        {embedded, true}

      embedded ->
        {embedded, false}
    end
  end
end
