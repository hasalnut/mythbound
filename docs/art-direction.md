# Mythbound art direction

How Mythbound should look, and how to change models, textures and lighting without rewriting game code.

## Style pillars

1. **Chunky low-poly.** Big, simple shapes with clear silhouettes. A wolf, a house or a dragon should be recognisable as a black shape.
2. **Bold colour, one palette per zone.** Saturated but harmonious; each zone owns its colours, so players know where they are at a glance.
3. **Light does the heavy lifting.** Strong sun, coloured fog and glowing accents make simple geometry look rich.
4. **Readable at phone size.** Enemies, telegraphs (red glow), loot and NPCs must stand out from the ground even on a small screen.
5. **Friendly fantasy, 12+.** Combat sparks and glows; no blood or gore.

## Zone palettes and lighting

Set these per zone (Lighting, Atmosphere and ColorCorrection). Fade between presets when players cross a zone border.

| Zone | Main colours | Accent | Time of day | Atmosphere | Grade |
| --- | --- | --- | --- | --- | --- |
| Hearthmoor | Meadow green #60963E, warm plaster #DECDA8, red roofs #A0322A | Lantern gold #FFD682 | ClockTime 14.5 | Density 0.28, soft blue haze | Saturation +0.12 |
| Whispering Woods | Deep green #2F5F37, moss #6E9A4A, bark #64442A | Fairy cyan #7FF0FF | ClockTime 16, light shafts | Density 0.4, green-grey | Slight green tint, contrast +0.1 |
| Fairy Glade | Lilac #B9A2E8, pale grass #A8D88A | Pink glow #FF8FD8 | ClockTime 19 (dusk) | Density 0.35, pink-lilac | Bloom up, saturation +0.2 |
| Labyrinth Ruins | Sandstone #C9B08A, old stone #8C857A | Ethereal teal #5FF5D2 | ClockTime 12, harsh | Density 0.2, dusty yellow | Contrast +0.15 |
| Ashen Peaks | Ash grey #6E6A66, charcoal #2E2B2A | Lava orange #FF6A1F | ClockTime 17, red sky | Density 0.45, warm grey | Warm tint, bloom on lava |
| Shattered Rift | Void purple #3A2058, black #141018 | Rift magenta #E04CFF | Night with a purple sky | Density 0.5, purple | Cool tint, strong bloom |

## Making it pop: checklist for each art pass

- **Lighting:** Future lighting technology; one strong sun; coloured Atmosphere; Bloom kept subtle and pushed only on glowing things.
- **Contrast:** dark ground under light props, or the other way round. Avoid mid-grey on mid-green.
- **Glow accents:** windows, crystals, orbs, the gate ward and fairy dust use Neon or emissive parts, plus a PointLight where it matters.
- **Silhouettes:** vary heights (tall pines next to low bushes, towers next to cottages).
- **Ground detail:** paths, flowers, rocks and grass tufts break up flat terrain; keep them cheap (no collision, no shadows, no queries).
- **VFX:** ParticleEmitters for fire, sparkles, dust and leaves; Trails or Beams on weapon swings; a flash on hits; red Highlight telegraphs before enemy attacks.
- **Motion:** idle animations on NPCs, swaying grass, bobbing fairies, chimney smoke.
- **Sound:** an ambience bed per zone, footsteps, hit sounds, a level-up chime and music per zone.
- **UI:** one theme everywhere (dark panel, gold edge, cream text) with icons rather than words where possible.

## Swappable assets (how to change models without touching game code)

The world is built by code (`src/server/Hearthmoor.luau`), which keeps the map in Git. Art is swapped through `src/server/Assets.luau`:

1. Store finished models in Studio under `ServerStorage/Assets/<Zone>/<Name>` (for example `ServerStorage/Assets/Hearthmoor/HouseSmall`), or directly in `ServerStorage/Assets`. Only those two levels are searched, so models nested inside other models are never picked up by mistake.
2. Give each scenery model a PrimaryPart at ground level, with its front facing -Z. Without a PrimaryPart, the bottom centre of its bounding box is put on the ground instead.
3. The world builder calls `Assets.place(name, cframe, parent, buildGrey, scale)`. `cframe` is the ground point, turned so -Z points the way the front should face. If a model with that name exists, a copy is placed there and all its parts are anchored; if not, `buildGrey` builds the grey version from code. `scale` resizes the replacement with `Model:ScaleTo`.
4. To change a house, tree or rock: put a model with the same name in `ServerStorage/Assets`. No code changes needed. Names in use:
   - `ElderHall` (31 × 24 studs, door facing south)
   - `HouseSmall` (21 × 21: HouseNorthEast and HouseSouth) and `HouseWide` (24 × 21: HouseWest and HouseEast). One model replaces every house of that size; the code still names each copy (HouseWest and so on).
   - `AppleTree` (village), `Tree` and `Pine` (scenery, scaled 0.9 to 1.6)
   - `Rock`: make it the size of a size-4 grey rock (about 6.4 × 3.6 × 5.2 studs); copies are scaled by size ÷ 4 (0.5 to 1.5).
   - `Well`, `Campfire` (a replacement campfire needs its own fire and light)
5. Creatures work the same way: a model named after the creature id (`wolf`, `boar`, usually in `Assets/Creatures`) with a HumanoidRootPart, a Humanoid whose HipHeight holds the body off the ground and, once animated, Motor6D joints or bones. Code unanchors its parts and adds health, speed, hit size and the red bite telegraph. A model without a HumanoidRootPart or Humanoid is skipped with a warning in Output, and the grey body is used.
6. `Assets` warns in Output if a model contains scripts. Remove them unless you wrote them.
7. Save the place after changing assets. Models live in the place, not in `src/`, so a place rebuilt from `src/` won't contain them. Keep a copy of each exported model in `assets/models/` too.

## Making models and textures

- **Blender, low-poly.** Keep triangle counts low (a few hundred for props, a few thousand for creatures). Import with Studio's 3D Importer (FBX or OBJ).
- **Colour with a palette texture.** UV-map faces onto a small palette image (a grid of flat colours). One texture per zone keeps memory low and colours consistent.
- **Materials:** use Roblox's built-in materials for most things. MaterialVariants (in MaterialService) can give terrain and parts a custom stylised look across the whole game. Keep SurfaceAppearance (full PBR textures) for a few hero items.
- **Terrain:** set each material's colour per zone with `Terrain:SetMaterialColor`, or use MaterialVariants for custom grass and rock.
- **Studio's generation tools:** Studio's MCP server can generate meshes, materials, procedural models and animations from a prompt. Use them for quick drafts and placeholders, then keep or replace the results.
- **Free assets:** Creator Store models are allowed after checking their licence. **Delete every Script, LocalScript and ModuleScript inside a free model before using it**, because free models can hide malicious scripts. Record each one in `assets/CREDITS.md`.

## Performance budget

- Aim for 60 fps on the slowest development PC, and keep phones in mind.
- Anchor all scenery. Switch off `CanCollide`, `CanQuery`, `CanTouch` and `CastShadow` on decoration such as leaves, grass and flowers.
- Reuse the same mesh many times rather than many slightly different meshes.
- Use StreamingEnabled once the map grows beyond Hearthmoor, and make client code cope with parts that aren't loaded yet.
- Keep shadow-casting lights to a handful per area.
