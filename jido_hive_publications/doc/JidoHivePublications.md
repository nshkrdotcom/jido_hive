# `JidoHivePublications`
[🔗](https://github.com/nshkrdotcom/jido_hive/blob/main/lib/jido_hive_publications.ex#L1)

Explicit publication extension over canonical Jido Hive room resources.

# `fetch_publication_run`

```elixir
@spec fetch_publication_run(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
```

# `list_publication_runs`

```elixir
@spec list_publication_runs(
  String.t(),
  keyword()
) :: {:ok, [map()]}
```

# `load_publication_workspace`

```elixir
@spec load_publication_workspace(String.t(), String.t(), String.t(), keyword()) ::
  map()
```

# `plan_publication`

```elixir
@spec plan_publication(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
```

# `publish`

```elixir
@spec publish(String.t(), String.t(), map(), map(), keyword()) ::
  {:ok, map()} | {:error, term()}
```

# `start_publication_run`

```elixir
@spec start_publication_run({String.t(), String.t()} | map(), map()) ::
  {:ok, map()} | {:error, term()}
```

# `workspace`

```elixir
@spec workspace(String.t(), String.t(), String.t(), keyword()) :: map()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
