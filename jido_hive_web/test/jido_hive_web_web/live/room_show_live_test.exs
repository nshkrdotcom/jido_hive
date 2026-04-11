defmodule JidoHiveWebWeb.RoomShowLiveTest do
  use JidoHiveWebWeb.ConnCase

  import Phoenix.LiveViewTest

  setup do
    previous =
      %{
        rooms_module: Application.get_env(:jido_hive_web, :rooms_module),
        room_session_module: Application.get_env(:jido_hive_web, :room_session_module),
        test_pid: Application.get_env(:jido_hive_web, :test_pid)
      }

    Application.put_env(:jido_hive_web, :rooms_module, JidoHiveWebWeb.Support.RoomsStub)

    Application.put_env(
      :jido_hive_web,
      :room_session_module,
      JidoHiveWebWeb.Support.RoomSessionStub
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

  test "renders room workflow, provenance, steering, and run controls", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/rooms/room-1")

    assert html =~ "data-screen=\"room-show\""
    assert html =~ "Inspect contradiction"
    assert html =~ "Question"
    assert html =~ "Shared Graph"
    assert html =~ "Steering Composer"

    assert_receive {:room_session_start, opts}
    assert opts[:room_id] == "room-1"
    assert render(view) =~ "Conversation"

    view
    |> element("#show-provenance")
    |> render_click()

    assert render(view) =~ "Send clarification"

    assert view
           |> element("#draft-form")
           |> render_submit(%{"draft" => %{"text" => "Need decision"}})

    assert_receive {:submit_chat, "Need decision"}
    assert render(view) =~ "Need decision"

    assert view
           |> element("#run-room-form")
           |> render_submit(%{
             "run" => %{"max_assignments" => "2", "assignment_timeout_ms" => "90000"}
           })

    assert_receive {:run_room, "room-1", opts}
    assert opts[:max_assignments] == 2
    assert opts[:assignment_timeout_ms] == 90_000
  end
end
