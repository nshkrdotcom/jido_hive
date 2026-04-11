defmodule JidoHiveWebWeb.PublicationShowLiveTest do
  use JidoHiveWebWeb.ConnCase

  import Phoenix.LiveViewTest

  setup do
    previous =
      %{
        publications_module: Application.get_env(:jido_hive_web, :publications_module),
        test_pid: Application.get_env(:jido_hive_web, :test_pid)
      }

    Application.put_env(
      :jido_hive_web,
      :publications_module,
      JidoHiveWebWeb.Support.PublicationsStub
    )

    Application.put_env(:jido_hive_web, :test_pid, self())

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:jido_hive_web, key)
        {key, value} -> Application.put_env(:jido_hive_web, key, value)
      end)
    end)

    :ok
  end

  test "renders publication workspace and publishes bindings", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/rooms/room-1/publish")

    assert html =~ "Draft"
    assert html =~ "Repository name"

    assert view
           |> element("#publish-form")
           |> render_submit(%{"publish" => %{"github" => %{"repo" => "nshkrdotcom/jido_hive"}}})

    assert_receive {:publish_room, "room-1", payload}
    assert payload["bindings"]["github"]["repo"] == "nshkrdotcom/jido_hive"
  end
end
