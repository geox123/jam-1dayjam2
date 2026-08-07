# Airebound

Airebound is a 2D, single-screen survival game for the 1-Day Jam #2. You are a small Balloon riding dangerous Air Currents: steer, take risks, and use a timed Gust to stay alive.

## Controls

- Arrow keys or WASD: steer the Balloon
- Space: release a Gust when ready
- Space after failure: retry

## Run locally

Open the project in Godot 4.7+ and run `main.tscn`.

For a headless rules check:

```text
godot --headless --path . --script res://tests/test_game_rules.gd
```

The game uses only procedural drawing and the built-in fallback font, so it has no external asset dependencies.
