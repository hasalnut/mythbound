# Mythbound

A free 3D fantasy action RPG with creature taming, built by one developer **on Roblox, in Luau**. Players pick a class, choose a path through the world and tame the mythical creatures they meet, from a fox in the meadows to a dragon they can ride. Friends play together on Roblox's free servers, on PC first and phones later.

## Status (15 November 2026)

- The place is published to Roblox (place 107679241076160) and edited in Studio; scripts changed there are copied back to `src/`.
- Slices 1–3 (quest loop with XP, levels and saving; class skills and mana; items, inventory, gathering and crafting) are built and pass solo play tests, including leaving and rejoining. Still open: the 2+ player co-op checks for Slices 0–3, and the friend play-test (see `docs/roadmap.md`).
- Next is Slice 4 (taming and companions). The developer plans to use Claude Fable for it.
- The earlier Godot 4.7 version of Phase 1 is kept on the Git branch `phase-1` for reference. It was tested and works; it is no longer the main line.

## Where things are

- `src/`: all game code, laid out for Rojo (see "Project layout").
- `Mythbound.rbxlx`: a place file built from `src/` by `python3 tools/build_place.py`. Open it in Roblox Studio. It is a build output: change `src/`, then rebuild, or sync with Rojo. Models in `ServerStorage/Assets` live only in the place, not in `src/`.
- `default.project.json`: the Rojo project (maps `src/` folders into Roblox services).
- `docs/roadmap.md`: the build plan as thin slices, each one playable end to end in co-op. Work through it in order.
- `docs/art-direction.md`: palettes, lighting per zone, the "make it pop" checklist, and how to swap models and textures without code changes.
- `docs/game-data.md`: every class, skill, creature, item, recipe, formula and spawn from the browser prototype. Distances there are metres; multiply by 3.5 for studs.
- `prototype/index.html`: the original browser prototype, the reference for game feel and world layout. Don't extend it.
- The master design doc is the Google Doc "Mythbound — Design Roadmap & Checklist": https://docs.google.com/document/d/1YuS9py-10JnDOG8KFSTsd_Qtp5ieERhaHzIVGHBLAhs/edit. It still describes the Godot plan in places; this file wins where they disagree.

## Agreed decisions

Updated 15 November 2026 (progression, saving and inventory key decided; mouse-look key added).

- **Engine:** Roblox, Luau. Chosen because the developer's rule was "Godot only if it runs more efficiently on PC and phones", and with 6+ players Roblox's free servers run the world, so no player's device has to host. Trade-offs accepted: the game exists only on Roblox, there are no custom shaders, and players need a Roblox account.
- **Players:** online co-op, **up to 8 per server** (set in Experience Settings > Places > Server Size). No player-versus-player damage. Never write code that assumes one player: loop over `Players:GetPlayers()`, keep per-player state in tables keyed by `Player`.
- **Platform:** PC first. Phones come after the PC version is fun (touch buttons already appear for attack, dash, lock-on, skills, bag and potion through ContextActionService). Console is free on Roblox but not a goal.
- **Input:** keyboard and mouse, laptop trackpad and game controller from the first build.
  - Every action needs a key or a single click; nothing may require right-drag or two mouse buttons. Roblox's Shift-lock needs each player to switch on "Shift Lock Switch" in Roblox's settings, so the game has its own mouse-look toggle (X): it locks the pointer to the centre so moving the mouse turns the camera, and pauses itself while a menu, dialogue or the bag is open.
  - The camera also turns with the left and right arrow keys or the right stick.
  - Current bindings: attack click/J/RT, dash C/B, talk and gather F/Y (ProximityPrompt), lock-on T/middle click/R3, first person V/L3, mouse-look X, skills Q/L1 and E/R1, bag Tab/D-pad up, potion H/D-pad down, controls panel F1. G is reserved for mounts. I and O stay as Roblox's camera zoom, so the bag is on Tab only (Tab is read directly because Roblox's player list also claims it).
- **Progression:** one level per player, shared by every class, capped at 20. Everyone who damaged a creature gets its full XP, quest credit and their own loot. Returning players see the class screen with their saved class picked and a "Continue journey" button.
- **Camera:** Roblox's default third-person camera (it already avoids walls), with lock-on, a first-person toggle and mouse-look.
- **Art:** stylised low-poly, flat colours, one palette per zone (green woods, ash-grey peaks, purple Rift). Built from parts and terrain in code for now; meshes from Blender later, swapped in through `ServerStorage/Assets`. Record any free asset in `assets/CREDITS.md` after checking its licence.
- **World:** Hearthmoor is the hub. Each path leads to a zone; on Roblox a zone can be a separate area of the same place or a separate place reached with TeleportService. Decide when building the Whispering Woods.
- **Price and rating:** free. Fantasy combat only: no blood or gore, no bad language. Aim for Roblox's "Mild" content maturity label. Friends-only play; no open chat features of our own.
- **Length:** 30 minutes to 1 hour for the first map (Hearthmoor, Whispering Woods, Ashen Peaks, Shattered Rift). New maps come after release.

## Version 1 (vertical slice)

Version 1 is done when it has:

- Hearthmoor and Whispering Woods fully playable, in co-op
- All 5 classes with at least 2 skills each
- Fox, Fairy and Ethereal Fox tameable
- The Minotaur King boss with the spare or slay choice
- Progress saved with DataStores, and controller support
- 30 to 45 minutes of finished play at 60 fps on the slowest PC used for development

Ask before building anything outside this list.

## Game rules

### Classes

Ninja, Tank, Mage, Priest and Beast Tamer. Stats (health, mana, attack and so on) are in `src/shared/ClassData.luau`; skills are in `src/shared/SkillData.luau` (both converted from `docs/game-data.md`). Each class has Q and E skills now; the Beast Tamer's (Tame Beast, Call of the Wild) show a "coming with taming" message until Slice 4. Planned later: 4 skills per class (unlocked at levels 1, 5, 10 and 15) plus an ultimate, and a talent tree with 2 branches per class.

### Taming

- **Beast Tamer:** can tame every creature, mythic ones included, and bring up to 3 companions at once.
- **Other classes:** can tame common creatures only (for now, just the fox), 1 companion at a time, plus 1 quest mount given by the story.
- **Food each creature accepts:**
  - Fox (common): Meat, from hunted animals
  - Fairy (rare, mythic): a Cookie (crafted from Wheat + Honey) or an Apple
  - Ethereal Fox (epic, mythic, mount): Ethereal Meat, from minotaurs
  - Rift Runner (epic, mythic, mount): Void Meat, from void serpents
  - Dragon (legendary, mythic, flying mount): a Fire Ball, crafted from 3 Ember Shards
- **Beast-Tamer-only beasts:** wolf, boar, bear, ember slime, minotaur, void serpent. Weaken one below 50% health, then use the Tame Beast skill.
- **Taming moment:** a trust meter fills while the player feeds the creature and stays calm. Higher-level creatures need better food or more of it.
- In co-op, the player who finishes the taming owns the creature. Two players can't tame the same creature at once.
- Tamed creatures are never killed permanently, only knocked out.
- Each class keeps a small taming bonus: Ninja tames skittish creatures more easily, Priest heals pets more, Tank's pets take less damage, Mage's pets gain elemental damage.
- Mounts: Dragon (flies), Ethereal Fox (fastest; 30% of attacks pass through), Rift Runner (blink-teleports forward).

### Creature behaviour

- Wolves are hostile and hunt as a pack (`pack = true` in `CreatureData`): when one spots or is hit by a player, wolves nearby join in, each going for the player closest to itself.
- Boars are neutral: only the boar that was hit fights back, and it stays on whoever hit it.
- In co-op a chasing hostile creature switches to another player who is at least 12 studs closer, and when its target dies it turns on whoever else is near instead of going home. A taunted creature keeps its target; a vanished Ninja can't be followed.
- Creatures give up when led too far from home, walk back healing, and respawn some time after dying.

### Items

Items, recipes, loot tables and gathering spots are in `src/shared/ItemData.luau`. Wheat (field), Honey (beehives, 25% chance of a 6 HP sting) and Apples (village apple trees) are gathered with F, each spot on its own per-player timer. The workbench crafts Cookies and Healing Potions. The Elder gives 3 Healing Potions with the first quest. Loot drops are per player: only the owner sees and picks up their drop.

### Story (main quest)

Elder Maren in Hearthmoor asks the player to collect 2 of the 3 Sigils to open the barrier around the Rift Heart:

- **Sylvan Sigil:** defeat the Minotaur King in the Labyrinth Ruins, then spare him (minotaurs become peaceful) or finish him (more XP).
- **Ember Sigil:** offer the Elder Dragon a Fire Ball to tame it, or fight and slay it (it can then never be tamed).
- **Moon Sigil:** give the Fairy Queen 3 cookies.

The Rift Wyrm is the final boss. Endings: seal the Rift or claim its power, plus class-only endings for the Priest (purify), the Beast Tamer (bond with the Wyrm) and the Ninja (seal it from inside). Version 1 only needs the Whispering Woods part. In co-op, quest progress belongs to each player; kills count for everyone who helped. Quests are defined in `src/shared/QuestData.luau`; the first is "Wolves at the Fence" (defeat 4 wolves, 50 XP).

## Project layout (Rojo)

```
src/shared/  -> ReplicatedStorage.Shared       Config, ClassData, CreatureData, SkillData, ItemData, QuestData,
                                                Progression (XP/level formulas), Net (RemoteEvents)
src/server/  -> ServerScriptService.Server     Main.server (entry), PlayerData (saves), Quests, Skills (mana, Q/E),
                                                Inventory (items, gathering, crafting), Drops (per-player loot),
                                                Assets (swappable models), Combat, Creature, Hearthmoor (world builder),
                                                PlayerSetup (class choice, weapons), Dummy, Interactables, Build
src/client/  -> StarterPlayerScripts.Client    Main.client (entry), ClassSelect, HUD, QuestTracker, InventoryUI,
                                                Controls, Effects, UI
ServerStorage/Assets (in the place only)       replacement models: Assets/Hearthmoor/<Name>, Assets/Creatures/<id>
```

File names: `Name.server.luau` = Script, `Name.client.luau` = LocalScript, `Name.luau` = ModuleScript.

## Roblox conventions

- **The server decides, clients ask.** Damage, health, mana, cooldown checks, AI, loot, crafting, taming and saves happen on the server. Clients send intentions through RemoteEvents in `Net.luau` (add new names to its list) and draw effects. Check every argument a client sends (`typeof`, finite numbers, ranges, cooldowns, distance to the workbench).
- Anything that can be hit is a Model tagged `Damageable` (CollectionService) with a Humanoid and the attributes `HitRadius`, `HitHeight`, `Hostile`, `Void`, `DamageReduction`. Always deal damage through `Combat.damage`; area skills use `Combat.targetsNear`, heals use `Combat.heal`, projectiles use `Combat.fireProjectile`.
- Game data lives in ModuleScripts under `src/shared` (like `ClassData`), not scattered through scripts.
- Values the client shows but the server owns travel as Player attributes: `Level`, `XP`, `XPNext`, `Mana`, `MaxMana`, `SavedClass`, `DataLoaded`. Character attributes: `Vanished` (Ninja), `Taunting` (Tank).
- **Art goes through `Assets`:** scenery is placed with `Assets.place(name, cframe, parent, buildGrey, scale?)`, and creatures use `Assets.find(id)`, so a model in `ServerStorage/Assets` replaces the grey version without code changes (see `docs/art-direction.md`).
- **Creatures and fresh terrain:** terrain built by code isn't solid for physics straight away, so new creatures are held anchored for 1.5 s after spawning. Any creature that falls below y = -60 is removed and respawned 3 s later. Keep both when adding new creature types.
- **Dialogue:** while a dialogue box is open, ProximityPrompts are switched off on that client, so F advances the dialogue instead of re-triggering the prompt.
- **ScreenGuis and billboards made by code** that should survive a respawn need `ResetOnSpawn = false`.
- Luau style: tabs, PascalCase module names, camelCase functions and variables, UPPER_CASE constants, type annotations on function parameters. Add `--!strict` to a file once it passes Script Analysis cleanly.
- Input goes through ContextActionService with a keyboard, a controller and (where it makes sense) a touch binding for every action. Menus put GuiService selection on a button when a controller is in use.
- Saves: `PlayerData.luau`. DataStoreService, one key per player (`player_<UserId>`), `version` field (now 2: added inventory and gifts; `migrate` fills in missing fields), `UpdateAsync`, retries, save on leave, every 3 minutes and on shutdown. Studio uses its own store (`PlayerData_Studio`) so tests never touch real saves. If a save can't be loaded, that session isn't saved, so a good save is never overwritten. Testing in Studio needs File > Experience Settings > Security > "Enable Studio Access to API Services" (on since 15 November).
- Performance: aim for 60 fps on modest PCs, and keep phones in mind: anchor scenery, keep part counts sensible, switch off `CanQuery`/`CanCollide`/`CastShadow` on decoration, and consider StreamingEnabled when the map grows.
- Distances are in studs: 1 stud is about 0.28 m, a character is about 5 studs tall. Prototype metres x 3.5 = studs.

## Working with Claude on this project

- Claude edits scripts in Studio through Roblox Studio's built-in MCP server. To bring them back into Git: File > Download a Copy (`.rbxl`), then extract every Script, LocalScript and ModuleScript into `src/` (Claude can do this and push), or copy the changed scripts by hand. Rebuilding `Mythbound.rbxlx` with `python3 tools/build_place.py` or syncing with Rojo still works for changes made in `src/`.
- To connect: in Studio open **Assistant > … > Manage MCP Servers**, switch on **Enable Studio as MCP server**, then use **Quick connect** for Claude Desktop or Claude Code. With that, Claude can read the place, run Luau and start play tests.
- Studio's MCP server starts solo play tests only. Multi-player tests are Test > Start Test Session > Server and Clients; the clients only connect when Studio is on screen, so the developer starts them, then Claude can inspect the session as a second Studio instance.
- Studio's simulated input can't move the mouse or act as a controller, so mouse-look turning and controller navigation are checked by hand.
- Without Studio access, say clearly that code is untested, and list what the developer should check.
- Save the place in Studio (File > Save to Roblox) at the end of each session.

## Next tasks

The full plan is `docs/roadmap.md`.

1. **Co-op checks with 2–3 players** (Test > Start Test Session > Server and Clients, Studio on screen): wolves pick between players; no friendly fire; kill XP, quest credit and loot reach everyone who hit a wolf, and each player's quest and drops are their own; Healing Light and Holy Nova heal allies; Taunt pulls wolves off a friend.
2. **Friend play-test:** set Server Size to 8 (File > Experience Settings > Places), invite a friend.
3. **Controller check:** D-pad navigation on the class screen and in the bag, once a controller is available.
4. **Slice 4: taming and companions** (planned for Claude Fable): foxes, the trust meter, companion AI, knocked out instead of killed, companion limits, the Beast Tamer's Tame Beast and Call of the Wild (currently stubs in `SkillData`), and saving companions.

## Workflow

- Test in Studio after every change and fix every error and warning in Output before calling a task done. For co-op features, test with at least 2 players.
- Keep commits small, one feature per branch, with a clear message.
- When a design decision changes, update this file and `docs/` in the same commit, and tell the developer so the Google Doc can be updated too.
- Ask before adding paid assets, plugins, or anything outside Version 1.
