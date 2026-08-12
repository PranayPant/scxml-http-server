# Pre-commit pipeline

This repo uses [Lefthook](https://github.com/evilmartians/lefthook) — a
blazing-fast, Rust-based Git hooks manager — to enforce code quality on every
commit. The pipeline is modeled after the `scxml-orchestrator` library so both
projects share identical formatting and linting discipline.

## What runs on `pre-commit`

See [`lefthook.yml`](./lefthook.yml). Stages run **in parallel**:

| Command                        | What it does                                                       |
| ------------------------------ | ------------------------------------------------------------------ |
| `mix format --check-formatted` | Fails if any `.ex`/`.exs` is not Styler+formatter clean            |
| `mix credo --strict`           | Fails on Credo issues (readability, design, refactoring, warnings) |

Both stages glob `*.{ex,exs}`, so untouched files are skipped.

> **Tests are intentionally omitted for now.** The plan is to design the test
> suites _after_ the HTTP engine implementation is done. Once real tests
> exist, add `mix test --stale` and `mix test --cover` as additional
> `pre-commit.commands` stages (as the reference library does).

## Setup (one-time)

1. Install Lefthook (pick your platform):
   - macOS: `brew install lefthook`
   - Windows: `winget install evilmartians.lefthook` (or `choco install lefthook` / `scoop install lefthook`)
   - Linux: `curl -1sLf 'https://dl.cloudsmith.io/public/lefthook/lefthook/setup.deb.sh' | sudo -E bash` then `sudo apt install lefthook`
2. Install the Elixir deps:

   ```sh
   mix deps.get
   ```

3. (Re)write the git hooks:

   ```sh
   lefthook install
   ```

After that, every `git commit` runs the format + credo checks.
Running `lefthook install` again is only needed after you edit `lefthook.yml`.

## Manual verification

Run each stage yourself to confirm everything is green before committing:

```sh
mix format --check-formatted
mix credo --strict
mix compile --warnings-as-errors
```

## Line endings

[`.gitattributes`](./.gitattributes) normalizes all text files to **LF** on
checkout. This keeps `mix format`, Credo's `LineEndings` check, and the
container toolchain consistent across platforms (including Windows). Do not
remove the `eol=lf` rules.

## Related

- Reference pipeline: `scxml-orchestrator` (`lefthook.yml`,
  `.formatter.exs`, `.credo.exs`)
- Tool docs: [lefthook](https://github.com/evilmartians/lefthook),
  [elixir_styler](https://github.com/adopt-liveview/elixir-styler),
  [credo](https://github.com/rrrene/credo)
