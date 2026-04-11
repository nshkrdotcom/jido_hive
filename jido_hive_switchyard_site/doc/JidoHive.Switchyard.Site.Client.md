# `JidoHive.Switchyard.Site.Client`

Thin site-side client helpers over `jido_hive_client`.

# `list_rooms`

```elixir
@spec list_rooms(
  String.t(),
  keyword()
) :: [JidoHiveClient.RoomCatalog.room_summary()]
```

# `load_provenance`

```elixir
@spec load_provenance(String.t(), String.t(), String.t(), keyword()) ::
  {:ok, map()} | {:error, :not_found}
```

# `load_publication_workspace`

```elixir
@spec load_publication_workspace(String.t(), String.t(), String.t(), keyword()) ::
  JidoHiveClient.PublicationWorkspace.t()
```

# `load_room_workspace`

```elixir
@spec load_room_workspace(String.t(), String.t(), keyword()) ::
  JidoHiveClient.RoomWorkspace.t()
```

# `publish`

```elixir
@spec publish(
  String.t(),
  String.t(),
  JidoHiveClient.PublicationWorkspace.t(),
  map(),
  keyword()
) ::
  {:ok, map()} | {:error, term()}
```

# `submit_steering`

```elixir
@spec submit_steering(String.t(), String.t(), map(), String.t(), keyword()) ::
  {:ok, map()} | {:error, term()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
