defmodule JidoHiveTermuiConsole.ConfigTest do
  use ExUnit.Case, async: false

  alias JidoHiveTermuiConsole.Config
  alias JidoHiveTermuiConsole.TestSupport

  setup do
    config_dir = TestSupport.tmp_dir()
    previous = Application.get_env(:jido_hive_termui_console, :config_dir)
    Application.put_env(:jido_hive_termui_console, :config_dir, config_dir)

    on_exit(fn ->
      if previous do
        Application.put_env(:jido_hive_termui_console, :config_dir, previous)
      else
        Application.delete_env(:jido_hive_termui_console, :config_dir)
      end

      File.rm_rf!(config_dir)
    end)

    %{config_dir: config_dir}
  end

  test "load falls back to defaults when config file does not exist" do
    assert Config.load() == %{
             "api_base_url" => "http://127.0.0.1:4000/api",
             "participant_id" => nil,
             "participant_role" => "coordinator",
             "authority_level" => "binding",
             "poll_interval_ms" => 500
           }
  end

  test "list/add/remove room ids through rooms.json" do
    assert Config.list_rooms() == []
    assert :ok = Config.add_room("room-a")
    assert :ok = Config.add_room("room-b")
    assert Config.list_rooms() == ["room-a", "room-b"]
    assert :ok = Config.remove_room("room-a")
    assert Config.list_rooms() == ["room-b"]
  end

  test "corrupt files fall back silently" do
    File.mkdir_p!(Config.config_dir())
    File.write!(Config.config_path(), "{not-json")
    File.write!(Config.rooms_path(), "{not-json")

    assert Config.load()["api_base_url"] == "http://127.0.0.1:4000/api"
    assert Config.load_rooms() == []
  end
end
