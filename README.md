# Mythbound

A free 3D fantasy RPG on Roblox. Choose a class, choose your path and tame the mythical creatures you meet, from a fox in the meadows to a dragon you can ride. Play with up to 8 friends on PC (phones later).

**Status:** playable in Roblox Studio. Hearthmoor, the five classes with two skills each, combat, wolves and boars, Elder Maren's first quest, XP and levels, saving, and items with gathering and crafting (roadmap Slices 0–3). Next: taming. The earlier Godot version of Phase 1 is on the `phase-1` branch.

## Play it in Roblox Studio

1. Install [Roblox Studio](https://create.roblox.com/) and sign in with your Roblox account.
2. Open `Mythbound.rbxlx` from this folder (File > Open from File).
3. Press **Play** (F5). The server builds Hearthmoor in a few seconds; choose a class and press **Begin journey**.
4. To try co-op on one computer: **Test** tab > **Start Test Session** > **Server and Clients**, pick 2 or 3 players.

Saving needs the published place and File > Experience Settings > Security > **Enable Studio Access to API Services**. Studio play tests use a separate save store, so they never touch real players' saves.

If anything breaks, the **Output** window (View > Output) shows the error and the script it came from.

| Action | Keyboard and mouse | Controller |
| --- | --- | --- |
| Move | WASD | Left stick |
| Look | Hold right mouse, arrow keys, or X for mouse-look | Right stick |
| Attack | Click or J | Right trigger |
| Jump / Dash | Space / C | A / B |
| Talk, read, use | F | Y |
| Lock on | T or middle click | R3 |
| Skills | Q / E | L1 / R1 |
| Bag (inventory, crafting) | Tab | D-pad up |
| Healing potion | H | D-pad down |
| Zoom | Scroll, or I / O | |
| First person | V | L3 |
| Controls panel | F1 | |

In Hearthmoor: talk to Elder Maren by the big red-roofed hall, practise on the training dummies east of the campfire, read the signpost on the north road, and fight the wolf packs outside the fence (west and east) or the boars to the south-west. Wolves glow red just before they bite: dash away.

## Let Claude work inside Studio

Roblox Studio has a built-in MCP server, which lets Claude Desktop or Claude Code read the place, run code and start play tests:

1. Install Claude Desktop (or Claude Code) and open it once.
2. In Studio: **Assistant** > **…** > **Manage MCP Servers** > switch on **Enable Studio as MCP server**.
3. Under **Quick connect**, choose Claude Desktop or Claude Code. A green dot shows when it's connected.
4. Open this repository in Claude and ask it to play-test.

## Editing the code

The code lives in `src/` as `.luau` files. Two ways to get changes into Studio:

- **Rebuild the place file:** `python3 tools/build_place.py`, then reopen `Mythbound.rbxlx`. The script also runs a quick check for unbalanced blocks.
- **Live sync with [Rojo](https://rojo.space/):** run `rojo serve` in this folder and connect with the Rojo plugin in Studio. Edits in VS Code appear in Studio as you save.

## Project files

| Path | What it is |
| --- | --- |
| `CLAUDE.md` | Project brief: agreed decisions, game rules, conventions and the next tasks |
| `src/` | The game code (shared, server and client) |
| `Mythbound.rbxlx` | Place file built from `src/`, ready to open in Studio |
| `default.project.json` | Rojo project file |
| `tools/build_place.py` | Builds the place file from `src/` |
| `docs/roadmap.md` | The build plan in thin slices, with what's done |
| `docs/art-direction.md` | Palettes, lighting and how to swap in real models |
| `docs/game-data.md` | Every class, creature, item and formula from the prototype |
| `prototype/index.html` | The original browser prototype (open it in a browser) |

The full design roadmap is kept in Google Docs.
