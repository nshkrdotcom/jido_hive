defmodule JidoHiveWebWeb.RoomIndexLiveTest do
  use JidoHiveWebWeb.ConnCase

  import Phoenix.LiveViewTest

  setup do
    previous =
      %{
        rooms_module: Application.get_env(:jido_hive_web, :rooms_module),
        test_pid: Application.get_env(:jido_hive_web, :test_pid)
      }

    Application.put_env(:jido_hive_web, :rooms_module, JidoHiveWebWeb.Support.RoomsStub)
    Application.put_env(:jido_hive_web, :test_pid, self())

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:jido_hive_web, key)
        {key, value} -> Application.put_env(:jido_hive_web, key, value)
      end)
    end)

    :ok
  end

  test "lists rooms and creates a room", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/rooms")

    assert html =~ "data-screen=\"room-index\""
    assert html =~ "Stabilize auth path"
    assert html =~ "Operator Guide"

    assert view
           |> element("#create-room-form")
           |> render_submit(%{"room" => %{"room_id" => "room-2", "brief" => "New room"}})

    assert_receive {:create_room,
                    %{"room_id" => "room-2", "brief" => "New room", "participants" => []}}

    assert_redirect(view, "/rooms/room-2")
  end
end
