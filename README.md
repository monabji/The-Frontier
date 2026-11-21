<img src="assets/icon.svg" width="64" height="64" alt="">

# The Frontier

A daily newspaper for AI and tech. One dated edition each morning, edited from a shared corpus, finite by design, free to read, archived forever.

- [Plan](docs/PLAN.md)
- [Phases](PHASES.md)
- [Glossary](GLOSSARY.md)
- [Decisions](docs/adr/)

## Status

Phase 0 — the press is installed. A Phoenix app on SQLite with Oban configured
serves one hardcoded story in the paper's real type: masthead, date line, lead,
source quote, readable at 390px and on a desktop. No sources, no editor, no
archive yet.

```bash
mise install
mix setup
mix phx.server   # http://localhost:4000
```

The paper's face is decided in [docs/DESIGN.md](docs/DESIGN.md).
