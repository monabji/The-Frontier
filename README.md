# The Frontier

The daily tech e-newspaper. One dated edition everyday at 06:00 IST.

![The Frontier front page in Broadsheet layout](assets/screenshot.png)

## Tech stack

- Elixir and Phoenix render HTML with HEEx templates.
- SQLite holds the data through Ecto.
- Oban runs the daily pipeline.
- Editions are stored as JSON and HTML files, so a printed day renders without the database.
- Newsreader and Fraunces are self-hosted.

## Run it

```bash
mise install
mix setup
mix phx.server
```

Open http://localhost:4000.

## Done

- [x] Phoenix app on SQLite with Oban
- [x] Hacker News, feed and Bluesky adapters
- [x] Canonical URLs and clustering into stories
- [x] Editor with grounding checks and a keyless desk
- [x] Dated edition artifacts and an archive
- [x] 06:00 job with a delayed-edition fallback and alerts
- [x] Anonymous reader identity and a saved taste profile

## To do

- [ ] Per-reader fold generation and caching, phase 8
- [ ] Late Wire with visible timestamps, phase 9
- [ ] Admin page, host setup and the 14-day launch streak, phase 10
