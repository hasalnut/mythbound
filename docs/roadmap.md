# Mythbound roadmap: thin slices

Each slice is a **complete, playable piece of the game in co-op**, from input to server to UI to save. A slice is small enough to finish in one or two sessions. Build each feature in its simplest end-to-end form first (grey boxes are fine) and deepen it in later slices. Don't build a system in isolation that players can't touch yet.

**Rules for every slice**

- Plan first: list the scripts to add or change and the RemoteEvents needed, then build.
- Play-test in Studio after each change: start play, read the output log, take a screen capture. Fix every error and warning.
- Test co-op with at least 2 players (Test > Clients and Servers) before calling the slice done.
- Keep the art at the slice's art level (see "Art levels" below). Visual polish happens in the art passes, not mid-slice.
- When the slice is done, tick its boxes here, update `CLAUDE.md` if a decision changed, and commit.

**Art levels**

- **Grey:** parts and terrain from code, flat colours. Fine for anything new.
- **Good:** final layout and silhouettes, zone palette and lighting, basic VFX and sound.
- **Polished:** custom meshes, animations, music, particle detail. Only in the art passes.

---

## Slice 0: Foundation check (now)

Goal: the starter is solid enough to build on.

- [x] Run through the checklist in `CLAUDE.md` > Next tasks for all 5 classes, and fix what's wrong.
- [x] Mouse-look toggle that doesn't need right-drag (for trackpads), plus keyboard camera turning.
- [x] Swappable assets: add `ServerStorage/Assets` and an `Assets.place(name, cframe)` helper that clones a model from there if it exists, otherwise builds the grey version from code. Use it for houses, trees, rocks, the well, the campfire and creatures, so art can be swapped later without code changes (see `docs/art-direction.md`).
- [ ] Co-op test with 3 players: wolves pick between players; no friendly fire.
- [ ] Publish privately, set server size to 8, and play once with a friend.

Done when: a friend can join, pick a class, fight wolves with you and talk to the Elder, with no errors in the output log.

## Slice 1: The first quest loop

Goal: the core loop of talk → fight → return → reward → progress saved.

- [x] Quest system (server): quests defined in `src/shared/QuestData.luau`; per-player quest state; objective tracking from events (creature defeated, item collected, place reached).
- [x] Elder Maren gives "Wolves at the Fence": defeat 4 wolves, then return.
- [x] Quest tracker UI (top right) and a "!" or "?" marker over the Elder.
- [x] XP and levels: XP from kills (shared by everyone who damaged the creature), level-up toast and effect; health and attack scale with level (formulas in `docs/game-data.md`).
- [x] Saving with DataStores: class, level, XP and quest state per player, with a `version` field. Load on join, save on leave and every few minutes.
- [ ] Co-op check (2+ players): kill XP and quest credit reach everyone who hit the wolf; each player's quest is separate.

Done when: a new player finishes the quest, levels up, leaves, rejoins, and still has the level and the finished quest. (Solo: done 15 November.)

## Slice 2: Class skills

Goal: classes feel different.

- [x] Mana bar with regeneration.
- [x] Skill 1 (Q) for every class, from `docs/game-data.md`: Ninja Vanish, Tank Taunt, Mage Fireball, Priest Healing Light, Beast Tamer Tame Beast (stub until Slice 4).
- [x] Cooldown icons on the HUD; touch buttons for phones.
- [x] Skill 2 (E) for every class: Shuriken Fan, Shield Slam, Frost Nova, Holy Nova, Call of the Wild (stub until Slice 4: it buffs companions).
- [ ] Healing affects allies in range (co-op); taunt pulls aggro from allies. Built; needs the 2-player test.

Done when: each class has 2 skills that work in co-op and show on the HUD. (Solo: done 15 November, except the Beast Tamer, whose skills need companions.)

## Slice 3: Items, inventory and crafting

Goal: things to pick up, carry and make.

- [x] Item data (`ItemData.luau`) and per-player inventory, saved.
- [x] Creatures drop loot (Meat from wolves and boars); pick up by walking over it. In co-op, each player gets their own drops (built; needs the 2-player test).
- [x] Gather Wheat from the field and Honey from the beehives (ProximityPrompt). Apples from the village apple trees too (the potion needs them).
- [x] Inventory screen (Tab, controller D-pad up), usable with mouse, controller and touch.
- [x] Workbench crafting: Cookie = Wheat + Honey; Health Potion recipe.
- [x] Use a potion (H, controller D-pad down). The Elder gives 3 potions with the first quest.

Done when: you can hunt, gather, craft a cookie and a potion, drink the potion, and keep everything after rejoining. (Solo: done 15 November.)

## Slice 4: Taming and companions

Goal: the game's signature feature, end to end, with the Fox.

- [ ] Foxes in the meadow (passive; they flee).
- [ ] Feed Meat to a fox (prompt) to fill a trust meter; it fails if you attack or move suddenly.
- [ ] A tamed fox follows you, fights your target, is knocked out instead of killed, and recovers after 30 seconds.
- [ ] Companion limits (1, or 3 for the Beast Tamer) and the Beast Tamer's Tame Beast skill on weakened wolves and boars.
- [ ] Companions are saved and come back when you rejoin; a simple companion panel lets you choose who's out.

Done when: two players each tame a fox, fight together with them, and still have them after rejoining.

## Slice 5: Whispering Woods and the Fairy Glade (grey, then good)

Goal: the first real zone beyond the village.

- [ ] Decide the zone layout: the same place, north of the gate, with StreamingEnabled turned on and client code made streaming-safe (recommended), or a separate place reached with TeleportService.
- [ ] The gate ward lifts after the first quest; waystones in Hearthmoor and the woods for fast travel.
- [ ] Woods layout (grey): paths, clearings, a river, wolves and bears; the Fairy Glade with fairies and the Fairy Queen.
- [ ] Fairies tameable with a Cookie or an Apple (mythic: Beast Tamer only).
- [ ] Moon Sigil quest: give the Fairy Queen 3 cookies.
- [ ] Art pass to "good" for Hearthmoor and the woods: zone palette, lighting preset, sound ambience.

Done when: a group can walk from Hearthmoor into the woods, tame a fairy, and earn the Moon Sigil.

## Slice 6: Labyrinth Ruins and the Minotaur King

Goal: the first boss and the first mount.

- [ ] Labyrinth Ruins (grey): corridors, traps, minotaurs that drop Ethereal Meat.
- [ ] Minotaur King boss: 2 phases, telegraphed attacks, health that scales with player count.
- [ ] Spare-or-slay choice → Sylvan Sigil. Sparing makes minotaurs peaceful for that player.
- [ ] Ethereal Fox: tame with Ethereal Meat (Beast Tamer), ride with G.
- [ ] Mount system: summon, ride, dismount; mount speed; works with friends nearby.

Done when: a group beats the Minotaur King, makes the choice, and someone rides an Ethereal Fox.

## Slice 7: Version 1 release pass

Goal: Hearthmoor, the woods and the ruins at release quality.

- [ ] Art pass to "polished": custom meshes for heroes and creatures, animations (attacks, walks, bites), VFX, music.
- [ ] Onboarding: the first 5 minutes teach move, attack, dash, talk and taming without walls of text.
- [ ] Settings: mouse sensitivity, invert-Y, music and effects volume.
- [ ] Performance: 60 fps on the slowest development PC; part counts and streaming checked.
- [ ] Content maturity questionnaire filled in (aim for "Mild"); game icon, thumbnails, description.
- [ ] Friends play-test; fix the top issues; make the game public.

Done when: Version 1 is live and 30 to 45 minutes of play hold up with friends.

## After Version 1

### Slice 8: Ashen Peaks and the Elder Dragon

- [ ] Ashen Peaks zone: lava, ember slimes (Ember Shards), climbing paths.
- [ ] Fire Ball crafting (3 Ember Shards).
- [ ] Elder Dragon: offer a Fire Ball to tame it, or fight and slay it (then it can never be tamed) → Ember Sigil.
- [ ] Dragon mount with flight (Space to fly, hold to climb); flying works in co-op.

### Slice 9: The Shattered Rift and the endings

- [ ] The Rift opens with 2 Sigils; void serpents (Void Meat), Rift Runner mount (blink forward).
- [ ] Rift Wyrm final boss.
- [ ] Endings: seal or claim, plus the Priest, Beast Tamer and Ninja class endings.

### Slice 10: Phones

- [ ] Touch layout for every action, larger UI, safe areas.
- [ ] Graphics settings for low-end phones (fewer particles, shorter view distance).
- [ ] Test on a low-end Android phone and an iPhone.

### Later

- More skills (4 per class plus an ultimate), talent trees, new maps, seasonal events.
