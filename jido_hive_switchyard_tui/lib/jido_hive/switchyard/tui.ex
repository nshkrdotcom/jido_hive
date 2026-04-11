defmodule JidoHive.Switchyard.TUI do
  @moduledoc """
  Jido Hive Switchyard composition entrypoint.
  """

  alias JidoHive.Switchyard.Site
  alias JidoHive.Switchyard.TUI.RoomsMount
  alias Switchyard.TUI.EscriptBootstrap

  @default_local_api_base_url "http://127.0.0.1:4000/api"

  @spec run(keyword()) :: :ok | {:error, term()}
  def run(opts \\ []) do
    bootstrap_module = Keyword.get(opts, :bootstrap_module, EscriptBootstrap)
    tui_module = Keyword.get(opts, :switchyard_tui_module, Switchyard.TUI)

    :ok = bootstrap_module.start_tui_dependencies()

    opts =
      opts
      |> Keyword.drop([:bootstrap_module, :switchyard_tui_module])
      |> Keyword.merge(
        site_modules: [Switchyard.Site.Local, Site],
        mount_modules: [RoomsMount],
        open_app: RoomsMount.id(),
        api_base_url: Keyword.get(opts, :api_base_url, @default_local_api_base_url),
        subject: Keyword.get(opts, :subject, Keyword.get(opts, :participant_id, "alice")),
        participant_id: Keyword.get(opts, :participant_id, "alice"),
        participant_role: Keyword.get(opts, :participant_role, "coordinator"),
        authority_level: Keyword.get(opts, :authority_level, "binding"),
        room_id: Keyword.get(opts, :room_id),
        tenant_id: Keyword.get(opts, :tenant_id, "workspace-local"),
        actor_id: Keyword.get(opts, :actor_id, "operator-1")
      )

    tui_module.run(opts)
  end
end
