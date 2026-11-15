# Mythbound game data (from the browser prototype)

These are the starting numbers used in `prototype/index.html`, taken directly from its code. Use them as the first values for the game data modules in `src/shared`, then rebalance. Distances are in metres (1 unit = 1 m), times in seconds, speeds in metres per second.

> **Rule changes since the prototype:** only the Beast Tamer can tame mythic creatures (Dragon, Fairy, Ethereal Fox, Rift Runner) and can bring up to 3 companions. Other classes can tame common creatures (the fox), 1 companion at a time, plus 1 quest mount. In the prototype any class could tame mythic creatures and the Beast Tamer brought 2. See `CLAUDE.md`.

## Classes

| Class | Role | HP | MP | Move speed | Attack | Damage reduction | Basic attack | Attack interval |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Ninja | Silent assassin | 110 | 80 | 9.6 | 12 | 10% | Melee, 3.3 m reach, 120° arc | 0.33 |
| Tank | Unbreakable guardian | 230 | 60 | 7.8 | 12 | 45% | Melee, 3.8 m reach, 143° arc | 0.7 |
| Mage | Arcane destroyer | 90 | 150 | 8.4 | 13 | 0% | Arcane bolt (ranged) | 0.5 |
| Priest | Light & healing | 125 | 130 | 8.4 | 10 | 12% | Holy bolt (ranged, ×2 vs void creatures) | 0.55 |
| Beast Tamer | Master of the wild | 135 | 90 | 8.8 | 9 | 15% | Arrow (ranged) | 0.5 |

### Skills

| Class | Key | Skill | MP | Cooldown | What it does (prototype numbers) |
| --- | --- | --- | --- | --- | --- |
| Ninja | Q | Vanish | 25 | 10 | Invisible for 6 s; enemies chasing you lose you; +35% move speed; next melee hit ×3 (Backstab) and ends stealth. |
| Ninja | E | Shuriken Fan | 18 | 4 | 5 shuriken in a fan (10° apart), each ×1.1 attack. |
| Tank | Q | Taunt | 15 | 8 | Every enemy within 22 m targets you for 6 s; you take 40% less damage (total reduction capped at 80%). |
| Tank | E | Shield Slam | 20 | 6 | Hits all enemies within 5.5 m for ×1.8 attack, stuns non-bosses 2 s and knocks them back 3 m. |
| Mage | Q | Fireball | 22 | 2.5 | Projectile that explodes for ×3 attack in a 5 m radius. |
| Mage | E | Frost Nova | 35 | 9 | Hits all enemies within 9 m for ×1.4 attack and freezes them 3 s (bosses 1 s). |
| Priest | Q | Healing Light | 30 | 6 | Heals you and companions within 20 m for 35% of max HP, then 4% max HP per second for 5 s. |
| Priest | E | Holy Nova | 30 | 7 | Hits all enemies within 8 m for ×2.2 attack (×2 more against void creatures); heals you and companions 10%. |
| Beast Tamer | Q | Tame Beast | 20 | 2 | Tames the nearest beast within 10 m if it is below 50% HP. Chance = 45% + 60% × (missing HP fraction). |
| Beast Tamer | E | Call of the Wild | 30 | 14 | Companions +60% damage and +30% speed for 8 s, healed 30%; summons a spirit wolf for 12 s. |

### Formulas

- Max HP = class HP × (1 + 0.12 × (level − 1)), rounded
- Max MP = class MP × (1 + 0.06 × (level − 1)), rounded
- Attack = class attack × (1 + 0.11 × (level − 1))
- XP to next level = 40 + 35 × level
- Damage taken = incoming × (1 − reduction), minimum 1; reduction = class value, +0.4 during Taunt, capped at 0.8
- Critical hit (melee): 12% chance, ×1.7
- MP regeneration: 5 + 2% of max MP per second. HP regeneration: 2% of max HP per second after 6 s without taking damage
- Potion: heals 45% of max HP
- Dash: 3× speed for 0.2 s, 0.3 s of invulnerability, 2.2 s cooldown
- Companion HP = creature HP × 1.6 × (1 + 0.1 × (player level − 1))
- Companion damage = creature damage (6 if none) × 1.5 × (1 + 0.12 × (player level − 1)) × 1.25 for a Beast Tamer × 2.2 for a unique creature
- Knocked-out companions recover after 30 s

## Creatures

| Creature | Rarity | HP | Damage | Speed | Behaviour | Aggro range | XP | Drops | Tamed with | Becomes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Deer | – | 35 | 0 | 7 | Passive (flees) | – | 6 | Meat ×1–2 | – | – |
| Boar | – | 55 | 7 | 6.5 | Neutral (fights back) | – | 12 | Meat ×1–2 | Beast Tamer: Tame Beast skill | Companion |
| Fox | Common | 30 | 6 | 7.5 | Passive (flees) | – | 0 | – | Meat | Companion |
| Wolf | – | 60 | 8 | 8 | Hostile | 16 | 15 | Meat ×1–2 | Beast Tamer: Tame Beast skill | Companion |
| Bear | – | 130 | 14 | 6.2 | Neutral (fights back) | – | 28 | Meat ×2–3 | Beast Tamer: Tame Beast skill | Companion |
| Fairy | Rare | 30 | 5 | 5 | Passive (flees) | – | 0 | – | Cookie or Apple | Companion |
| Minotaur | – | 170 | 16 | 6.2 | Hostile | 18 | 45 | Ethereal Meat ×1 (60%) | Beast Tamer: Tame Beast skill | Companion |
| Minotaur King (boss) | – | 650 | 22 | 6.8 | Hostile | 20 | 250 | Ethereal Meat ×2 | – | – |
| Ethereal Fox | Epic | 90 | 10 | 10 | Passive (flees) | – | 0 | – | Ethereal Meat | Mount, ×2.6 speed |
| Ember Slime | – | 45 | 9 | 4.2 | Hostile | 12 | 13 | Ember Shard ×1–2 | Beast Tamer: Tame Beast skill | Companion |
| Elder Dragon (boss) | Legendary | 950 | 28 | 7 | Sleeps; talk, tame or fight | – | 400 | – | Fire Ball | Mount, ×2.4 speed, flies |
| Void Serpent (void) | – | 95 | 13 | 7 | Hostile | 18 | 32 | Void Meat ×1 (75%) | Beast Tamer: Tame Beast skill | Companion |
| Rift Runner | Epic | 80 | 11 | 9 | Passive (flees) | – | 0 | – | Void Meat | Mount, ×2.3 speed, blinks |
| Void Wraith (void, ranged) | – | 70 | 11 | 5 | Hostile | 20 | 28 | Void Meat ×1 (30%) | – | – |
| Rift Wyrm (boss, void, ranged) | – | 1700 | 26 | 7.5 | Hostile | 30 | 600 | – | – | Companion only via the Beast Tamer "Bond" ending |

Ninjas are noticed at half the normal aggro range. Rift Runners blink 12–18 m away if you approach mounted or attack near them, so they must be approached on foot. Boss notes: the Minotaur King slams the ground every 7 s (×1.5 damage, 7.5 m radius, 0.9 s warning) and yields at 12% HP; the Elder Dragon breathes 5 fireballs every 4.5 s; the Rift Wyrm fires 3 void orbs every 2.8 s and summons 3 wraiths at 50% HP. The Minotaur King and Rift Wyrm enrage below 25% HP (×1.35 damage and attack speed).

## Items and crafting

| Item | Where it comes from |
| --- | --- |
| Meat | Deer, boars, wolves, bears |
| Apple | Apple trees in Hearthmoor (1–2 every 40 s) |
| Wheat | Wheat field in Hearthmoor (every 30 s) |
| Honey | Beehives in Hearthmoor (every 35 s; 25% chance of a 6 HP sting) |
| Cookie | Crafted |
| Healing Potion | Crafted; 3 from the Elder's starting gift |
| Ember Shard | Ember slimes; ember crystals in the Ashen Peaks (every 50 s) |
| Fire Ball | Crafted |
| Ethereal Meat | Minotaurs (60%); the Minotaur King |
| Void Meat | Void serpents (75%), void wraiths (30%) |
| Fairy Lantern | Crafted |

| Recipe | Ingredients | Use |
| --- | --- | --- |
| Cookie | 1× Wheat + 1× Honey | Fairies adore them. The Fairy Queen wants three. |
| Healing Potion | 1× Apple + 1× Honey | Restores 45% health (H). |
| Fire Ball | 3× Ember Shard | A living flame. Offer it to the Elder Dragon. |
| Fairy Lantern | 1× Apple + 1× Honey + 1× Ember Shard | Use it anywhere to lure a fairy to you. |

## World layout (prototype)

The prototype map is 480 × 480 m, centred on (0, 0). North is −z. Hearthmoor sits at the centre-south; paths lead west (woods), north (peaks) and east (rift).

| Landmark | Position (x, z) | Radius |
| --- | --- | --- |
| Hearthmoor Village | (0, 40) | 44 m |
| The Crossroads | (0, -10) | 10 m |
| Fairy Glade | (-185, 55) | 28 m |
| Labyrinth Ruins | (-170, -125) | 34 m |
| Moonlit Grove | (-125, -172) | 22 m |
| Dragon's Den | (0, -195) | 30 m |
| The Rift Heart | (192, -20) | 32 m |
| Mirror Lake | (22, 132) | 30 m |

| Spawn group | Centre (x, z) | Radius | Count |
| --- | --- | --- | --- |
| Deer | (20, 70) | 45 m | 6 |
| Deer | (-45, 95) | 35 m | 4 |
| Boar | (45, 15) | 35 m | 4 |
| Boar | (-55, 5) | 30 m | 3 |
| Fox | (-35, 85) | 35 m | 3 |
| Fox | (50, 75) | 30 m | 3 |
| Fox | (-30, -30) | 20 m | 2 |
| Wolf | (-110, -20) | 40 m | 5 |
| Wolf | (-150, -60) | 30 m | 4 |
| Boar | (-100, 35) | 30 m | 3 |
| Bear | (-140, 30) | 30 m | 2 |
| Bear | (-205, -30) | 20 m | 2 |
| Fox | (-95, 10) | 30 m | 3 |
| Deer | (-130, 0) | 40 m | 4 |
| Fairy | (-185, 55) | 16 m | 4 |
| Minotaur | (-170, -125) | 23 m | 4 |
| Minotaur King | (-170, -125) | 1 m | 1 |
| Ethereal Fox | (-125, -172) | 12 m | 2 |
| Ember Slime | (0, -100) | 30 m | 5 |
| Ember Slime | (-20, -150) | 25 m | 4 |
| Ember Slime | (22, -160) | 18 m | 3 |
| Elder Dragon | (0, -202) | 1 m | 1 |
| Void Serpent | (110, -20) | 30 m | 4 |
| Void Serpent | (150, 30) | 25 m | 3 |
| Void Serpent | (140, -70) | 25 m | 3 |
| Rift Runner | (118, 12) | 30 m | 3 |
| Rift Runner | (158, -52) | 22 m | 2 |
| Void Wraith | (100, -50) | 25 m | 3 |
| Void Wraith | (160, 5) | 22 m | 3 |
| Rift Wyrm | (192, -20) | 1 m | 1 |

Non-unique creatures respawn 45 s after death (60 s after being tamed), away from the player.
