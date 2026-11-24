# The Diabolical Doctor — native Godot port

Open `project.godot` in **Godot 4.7** and press **F5**. The main scene is `game/main.tscn`.
The game runs entirely in Godot: no browser, JavaScript runtime, sprite exporter, or local server is needed.

[Game progression plan](PROGRESSION_PLAN.md) records the mission-first opening, hybrid mission
formats, clone wake-ups, walkable lab, successive endings and the one-time perception break. Normal startup now shows a
basic title and four game slots. Each slot keeps its own unlocks, Intel and mission summary in
`user://games/slot_1` through `slot_4`; Game 1 copies existing flat saves when first selected and
leaves the originals intact. Selecting a slot begins a new mission with its saved progression;
mid-mission resume is not implemented. The first wave opens with a short green teleport arrival.
Keyboard/controller focus and Back work throughout. Pause → Title Screen allows switching games.
`--practice` and explicit test/wave hooks retain their direct-entry workflows.

Current playable mission: a **rainy street with parked vehicles** for rebuilding the art.
The 3200×2200 map doubles the old width and height (four times the area), with asphalt, pavement,
crosswalks, puddles, rain and 20 streetlights scaled for the 128px scientist. Selecting a game starts
the current five-wave cops-only street prototype. `--practice` opens the enemy-free art studio;
movement, independent aiming, equipped weapons, recoil and effects remain live there, while
testing cannot kill the character or advance the run. **Esc / Start → Weapon Lab** changes
the loadout and returns to the current mode without a difficulty screen.
The bionic arm is an additional back-mounted mechanical limb. Both natural arms remain;
**LT / right mouse** always shoves. **RT / left mouse** fires both equipped guns;
**right-stick click / middle mouse** fires only the mechanical gun. Its articulated segments
have generated normal maps and share the live sprite reflections, without a ComfyUI batch.
The previous combat content is retained for rebuilding it one piece at a time. Explicit
`-- --combat` runs it; `art/character_studio` in project settings controls the default. Existing
combat test scripts use combat mode, while `game/tests/character_studio_test.gd` is run with
`-- --character-studio` and checks practice plus first-world waves. `-- --blank-studio` uses the
neutral grid instead. **5 / controller Back** cycles night, dusk and daylight.

Streetlights have dark hoods and cast light downward. One cached 800×550 water field supplies
the floor, lamp streaks, live laser/bolt reflections and character reflections. Reflections mirror
the current Sprite2D textures and transforms, including the scientist's arm and gun layers; no
extra animation rig, per-actor viewport or texture readback is involved. The same system accepts
future Sprite2D actors and the existing enemy sheet renderer. Off-screen actors and dry regions
are culled; rays are capped at 16. Practice mode remains enemy-free.
`game/tests/wet_reflections_test.gd -- --character-studio` checks moving beams, bolt trails,
reflection expiry/budget, shared textures, grounded transforms, actor cleanup and enemy sheets.
Streetlight collision follows the small metal base at its actual rendered scale. It blocks
walking, navigation and dashing in the opening, blank studio and other outdoor themes; the
overhead light fixture does not create a tall invisible wall. Bases are permanent fixtures.

Seven vehicle sheets in `art/vehicles` provide 56 elevated views: DeLorean DMC-12, wood-paneled
Grand Wagoneer, burgundy sedan, mustard hatchback, cream cargo van, blue pickup and an '80s police
sedan. `tools/vehicles/package_sheets.py` copies the generated masters and records view bounds
without editing their pixels. Curb parking chooses 16–20 vehicles using a seed retained through
Weapon Lab visits; a fresh game gets a new arrangement. Cars have solid, destructible footprints,
stay clear of crossings, lamps and the starting area, and use the shared puddle reflection pass.
Collision widths come from each view's rendered sprite bounds, with a small bumper clearance
for the scientist's head beyond his hit circle. The ground depth excludes the elevated body
height, and wheels remain anchored to the same collision/sorting edge. Parking slots account
for these complete footprints, rather than the old undersized nominal car dimensions.
The gameplay character's origin is now at his feet, matching the vehicle tire/contact line.
The complete rig is raised out of its former 16.5-pixel shin-origin offset, so collision, y-sort,
weapons and puddle reflections use the same ground plane. Pill scaling stays grounded; airborne
poses lift only the rig while retaining their ground sort position. A character in front draws
over the car's lower body; a character behind can be occluded normally. The graphical
`game/tests/character_ground_test.gd -- --character-studio --render-check` checks both cases
using rendered overlapping pixels, as well as feet, scaling and muzzle alignment.
At least two cruisers alternate double red/blue roof flashes, with staggered phases and real
light/glow anchored to the lenses. The cars remain parked and contain no enemy spawns.
Each lens flash uses a cached mask of its painted glass and a measured per-view center; the
sideways and diagonal views keep their original lens shapes without rectangular spill onto
the roof or trim. `police_lens_alignment_test.gd -- --render-check` verifies all eight views
against the rendered unlit glass pixels.
Roof lights use 235-unit PointLight2D falloff at a 60-unit light height, so nearby normal-mapped
faces, coat folds, arm layers and weapons respond to red/blue flashes. Up to eight active roof
reflections use the same mirrored foot plane as the vehicle and share the puddle mask, ripple
and flash clock. They disappear during the dark interval and when a cruiser is destroyed.
`game/tests/parked_vehicle_test.gd -- --character-studio` checks the assets, 48 layout seeds,
collision corridors, persistent seeds and the live lightbar timing/anchors.
`game/tests/streetlight_collision_test.gd -- --character-studio` checks normal/shrunk/enlarged
walking contacts, walking around the base and dash blocking. The graphical
`game/tests/police_lighting_test.gd -- --character-studio` verifies red/blue illumination on
actual normal-mapped body pixels without a sprite tint.

The pause menu also provides **Test Shrinking Pill**, **Test Enlargement Pill**, and **Test Tesla
Coil**, granting preview charges without enabling enemy spawns. Pills last 10 seconds: shrinking
uses 55% size and collision radius; enlargement uses 160% and allows walking over enemies explicitly
classified `small` in `data/enemies.json` to stomp them. Flying enemies, civilians, vehicles and
ordinary medium/large targets are excluded. Pills replace the opposite effect and refresh rather
than multiply. Expiry restores the original size, hitbox and ground contact.
The Tesla Coil stays planted for 15 seconds. Its random 0.25–0.65-second pulses damage enemies
between it and the player only while the player is within **240 world units** and the connection
is clear of walls. Leaving range stops the link; re-entering reconnects while its lifetime remains.
All three supplies also have normal depot kits and paid refills in combat mode.

The player uses the new scientist art from `character/art/scientist_h3`: native 128px layers,
32 idle frames and a 34-frame walk at 24fps. Completed studies 37/38 supply the straight-arm aim
banks, and study 39 supplies a front-facing bridge for the three-frame (125ms) body turn. The
primary weapon keeps the same physical hand: near-arm view facing right, far-arm view facing left,
with shoulder and draw-order changes during the turn. Near/far view changes do not swap loadouts.
Aiming stays extended, including fast flicks; the incorrect apex fold and static shoulder cap
overlays have been removed. Sleeve roots are normalized, and recoil moves the grip while keeping
the shoulder pinned. The replacement forearm-first raise is prepared in
`export/comfyui/scientist-modular/natural-arm-raise`: elbow bends while upper arm stays horizontal,
then opens during the shoulder lift, arriving straight overhead. Run `Queue Natural Arm Raise.bat`
for two five-second near/far references; review and import those before enabling the new gesture.
Native sheets are 128px; world scale is 0.75.
Hands cover live procedural gun grips; weapon modules, muzzles, beams, hit flashes and melee
continue through the existing rig. New matched straight-arm recoil commissions are prepared in
`export/comfyui/scientist-modular/straight-arm-recoil`; the game currently uses its shoulder-pinned
recoil warp. Cutout masks and silhouette-derived normals remain an initial art pass.
Rebuild the assets with `tools/pixelstudio/import_h3_scientist.py` in ComfyUI's Python environment.
`character/tests/scientist_sprite_test.gd` checks the rig; pass `-- --render-check` with a graphical
renderer to verify actual frame pixels, including the lit texture path. CanvasTexture frames use
individual image textures because a nested AtlasTexture loses its region when rendered.

Scratch level music: `audio/doctor_diabolical_scratch.mp3` loops during gameplay in both street and practice modes, including the train heist,
at −14 dB beneath the effects, continuing through the supply depot without restarting between waves.
It pauses with the game and stops when the run ends. **M** mutes all audio.

The Diabolical Doctor is a Brotato-style arena game. You build a doomsday weapon, then survive 20 waves of police in a
single 1,600×1,100 arena (`levels/arena_level.gd`). Waves are back to back: 30 s, then +5 s a wave up to 60 s. The
supply depot opens between waves. Bosses arrive on waves 5, 10, 12, 15, 18 and 20 (Captain Ironclad, Static
Surge, Velvet Viper, Glacia, Dr. Violet Vex, Omega Paragon). Surviving wave 20 wins the run.

**Dr. Violet Vex**, wave 18, is a competing evil scientist with long violet hair, laboratory goggles,
a white coat and twin cyan/magenta laser blasters. She alternates committed, warned volleys with
destructible laser sentries and timed shock mines. Laser aim locks before firing; moving out of the
warning dodges the volley. She pauses to attack and recovers afterwards. Below half health she fires
four pairs instead of three and can place a third mine. At most two sentries and five mines can remain
active. Shooting her gadgets removes them; defeating her shuts down the rest and her remaining lasers.
Disguise cancels her current attack, and freeze/time-stop pause it. Tests: `game/tests/rival_scientist_test.gd`.

**Telescoping Monocle II.** Buying the Monocle twice upgrades its close aim guide into a crosshair.
With a controller it sits at the main gun's full current range, measured from its muzzle; range upgrades
move it outward. With mouse aim it follows the actual cursor. The second copy is labelled II in the shop,
and no third copy is offered. Selling a copy returns it to level I; selling both removes the guide.

**Reinforcements and consumables.** Plainclothes New York cops in jeans and white trainers arrive from
wave 2, charging police interceptors from 4, rifle SWAT from 6, SWAT carrying both ballistic shields and
assault rifles from 7, robot dogs from 9, National Guard rifle squads from 12, and tanks from 15. Difficulty
can bring these forward by up to three waves. SWAT shields lead mixed rifle teams; frontal direct hits
deal 35% damage, while flanking, freezing, explosions and lightning bypass protection. Robot dogs wind
up before lunging. Cars warn along a lane before committing to a straight charge and recover after a
crash; at most two cars and one tank can be alive or arriving. Tanks mark their cannon aim, then launch
a slow explosive shell. All ground units respect props. Mechanical units resist poison and take extra lightning damage.
Tanks have 248-pixel tracks and span about 310 pixels including the gun, with a 104-pixel collision radius.
Moving vehicles keep the same raised-roof perspective as parked cars at every heading, with round rubber
tyres and metal hubs. Cars and tanks spawn only in City Streets and Harbour, never indoors or on rooftops.

The depot has a dedicated consumable shelf: **Disguise** (14 scrap), **Grenade** (10), and **Teleport Pair**
(18), with the normal wave price scaling. Carry up to three of each, independently of weapons and arm
equipment. **X / Q** uses the selected supply; **D-pad Up / E** switches supplies. Y rerolls in the shop.
Disguise replaces the scientist with an overcoat, hat and sunglasses for four seconds, breaking enemy and
boss pursuit and cancelling their committed attacks. Firing or throwing a grenade reveals you; shots
already in flight remain dangerous. Grenades fly along your aim and burst after 0.85 seconds. One teleport
kit pays for two pads: press Y once to place each, leave the pad, then enter either for one trip. Both pads
vanish after that trip. An unused deployed kit is returned at wave end. Carried supplies survive waves;
a fresh run clears them. Interaction checks and optional captures: `game/tests/reinforcements_test.gd`.

**Flow:** title, then the Lab (name the weapon; pick a starting ammo/frame once unlocked), then difficulty, then wave 1, then the shop, then the next wave, and so on.

The scientist moves 10% faster while neither the main gun nor an equipped off-hand gun is firing.
Releasing the triggers restores the boost immediately; speed upgrades and slows still apply.

**Difficulty progression:** Petty Crook is available on a fresh profile. Reaching wave 20 on an unlocked
difficulty permanently opens the next difficulty; beating the final boss is not required. Locked cards use
a lock icon. This progress is saved with the item unlocks.

**Blueprint drops and jewel cases:** Captain Ironclad drops the Rocket Boots blueprint until it has been
collected. Walking onto it permanently unlocks the existing Rocket Boots speed upgrade in shops from wave 5
onward, including future runs. It does not grant a free equipped pair. Blueprints are never vacuum-collected
at wave end; missed blueprints carry to a visible spot near the next wave's spawn, within the same run.
Museum jewel cases have 240 HP (30 starting laser hits), show cracks and a damage bar, and shatter under
bolts, bullets, beams, razors or explosions. Shattering removes their collision and navigation obstruction,
leaves glass shards and spills three collectible gems worth 4 scrap each before payout modifiers. One case
per museum can contain an uncollected Disintegration Lens, Absolute Zero Core or Moon Laser Uplink blueprint.
Collecting it permanently opens that module's shop pool from wave 5 onward; discovering it alone does not.

**Train heist.** One wave per run, picked at random from waves 7, 8 or 9 (`data/rules.json` `heist.waves`; never a
boss wave), swaps the arena for a long armoured train (`levels/train_level.gd`). The villain boards at the caboose
and fights east through 28 connected cars: a caboose, repeating passenger/dining/mail/freight/first-class cars,
and a final vault car. This is four times the original car count.
Each car is a room with destructible seats, mail racks, freight containers or safes, joined by narrow gangway
doors. Cops board the villain's car and the two cars ahead (`game/train_heist.gd`), and the camera follows along
the train. The heist lasts 180 seconds (`heist.duration` in `data/rules.json`), three times the normal 60-second cap, for the longer
route. The floor uses 2,048-pixel texture tiles so the full train can render in a browser.
Stepping onto the striped vault strongroom at the front of the vault car
before the timer ends cracks the vault: the wave ends at once ("VAULT CRACKED!"). The HUD shows a car-by-car
progress bar, the current car and the reward. If the timer runs out first, the train gets away: the wave still
counts as survived, but there is no reward.

Each difficulty has its own heist reward (`heist.rewards`). The first vault on that difficulty permanently unlocks
the module for shops, saved like the blueprints. Every successful heist also installs a free copy for the rest
of the run. All five are drawn on the gun:

| Difficulty | Reward | Effect | On the gun |
|---|---|---|---|
| Petty Crook | Gold Bullion Ballast | +2 armor, +15% scrap | gold bar under the barrel |
| Nuisance | Rail Spike Bayonet | +1 pierce, +3 base damage | iron rail spike under the muzzle |
| Menace | Steam Piston Rings | +25% fire rate, +10% move speed | brass rings on the barrel, puffing steam |
| Supervillain | Locomotive Firebox | +4 burn/sec, +15% damage | glowing coal firebox under the gun |
| Arch-Nemesis | Express Headlamp | +90 range, +12% crit, +25% damage | big brass headlamp on top |

To play the heist directly: `--wave 8 --heist` (after `--`).

**Velvet Viper and boss rewards.** Wave 12 adds Velvet Viper, an adult heroine in a plum bodysuit,
patterned stockings, mask and shoulder missile pods. Her pink seekers track across the arena and over
props for up to 24 seconds; any bolt, bullet, razor, beam, grapple or player explosion can destroy them.
There are at most six live seekers. She warns for 0.55 seconds before rushing along a fixed three-leg
zigzag, stops on props and recovers for 0.85 seconds. Below half HP she moves faster and fires larger salvos.
Defeating her clears the remaining seekers and drops the **Triple Seeker Rack** blueprint. Collecting it
permanently adds the Rare secondary launcher (48 base scrap) to shops from wave 5 onward. It uses the
Bionic Arm slot and fires three rockets at the nearest hostile foes within 500 units every five seconds,
spreading targets when possible and reacquiring if one dies. Rockets collide with props and explode.

Viper also has a **20%** chance to drop the **Viper Zigzag** blueprint; Ironclad has the same chance to
drop **Ironclad Leap**, alongside his usual Rocket Boots blueprint. Collected rare blueprints add Epic
shop abilities (62 / 68 base scrap). These use a separate **Y / F action slot**, leaving the secondary
weapon equipped: zigzag makes three damaging dashes on a seven-second cooldown; leap travels up to
245 units and lands in a 115-unit ground slam on a ten-second cooldown. Movement input sets their
direction, otherwise aim does. Props stop both. The newest bought action equips B; selling it restores
the previous owned action. Collecting blueprints unlocks shop availability, not free equipment. Uncollected
blueprints carry to the next wave, and unlocked blueprints do not drop again.
Interaction tests and optional capture: `game/tests/viper_test.gd`.

**Electrode Helmet:** a Rare, 28-scrap wire-cage helmet with copper electrodes, blue glows and normal-mapped
metal. Every 1.5 seconds it automatically deals 3 damage to up to 3 enemies within 110 units of the player;
chain jumps must be within 80 units and cannot cross walls. It ignores civilians and allies and takes one
purchase, with no weapon slot required. Street lamp bases sit on the concrete perimeter sidewalks,
leaving the traffic lanes and central crossing clear.

**Patience Capacitor:** a Rare, 32-scrap laser module available whenever a laser is equipped, with one
purchase per run. Release that laser's trigger to store charge: 0.75 seconds gives 1.75× damage, and
1.5 seconds caps at 2.5×. Its next shot spends the charge; holding fire never refills it. Every nozzle
in a split volley receives the same bonus. Bolts, piercing beams, extra laser barrels and rear lasers
are supported, with independent charge per gun. Sustained beams spend it on the opening damage tick.
Non-laser shots gain no bonus. Copper charge windows and a HUD meter show the stored power; charged
shots turn amber-white. Charge resets each wave. Checks: `game/tests/capacitor_test.gd`.

**Combat readability.** The HUD flashes a red screen border on every hit and pulses it (with the HP bar)
below 30% health. Edge arrows point at off-screen threats: gold for the boss, orange for vehicles, and
flickering for anything winding up an attack (car charges, tank shells, boss charges and lasers). Enemy
shots have a dark outline, a white core and a short trail showing their heading. Gunmen paint a red laser
sight on the villain about half a second before firing. Baton cops (0.26 s) and riot police (0.42 s, with a
shield step) wind up visibly before a blow and miss if the villain steps out of reach; K9s and drones still
bite instantly. Chasers fan out at range instead of queueing, K9s gallop, and drones weave. The game-over
screen also shows the weapon's name and the furthest wave reached.

Weapon stats always show **Pierce**, including `0` for no extra penetrations, numeric upgrades and `∞`
for unlimited laser beams. The Laser row now simply says `bolt` or `beam`.

Player-facing copy stays brief: short unlock notices, item effects, prices and combat stats. The Lab and
difficulty picker use lock icons without progression instructions; the HUD omits unused arm-slot labels,
boss move descriptions and repeated action explanations. The shop uses its inline sale confirmation and price.

Captain Ironclad moves 1.95× faster and has about 41% more HP than his previous tuning. He charges earlier,
with a 0.5-second windup and shorter recovery, and slams in 0.8 seconds with a 115-unit warning circle.
Below half health he moves another 18% faster, charges more often, and slams in 0.65 seconds with a
130-unit circle. Telegraphs match the damage area. Other hero bosses retain their own tuning.

Drones take double lightning damage (chain jumps, Electrode Helmet, live Shock Grapple chain). They are
immune to direct poison damage, poison stacks and poison spread. A toxin-equipped shot still deals its
ordinary weapon impact. Resistances live in the drone's `damage_taken` table in `data/enemies.json`.

**Starting weapon, part swaps and unlocks.** Every run starts with a **Laser Ray Pistol** (Laser ammo + Ray Pistol
frame). Without upgrades the Laser fires a **laser bolt**: a fast (900 px/s) red dash that stops at the first cop
it hits, like a bullet. Damage is still 8, so it one-shots a wave-1 cop. The **piercing beam** (instant, hits every
cop in the line) has to be acquired: the **Focusing Lens** (Rare module, 34 scrap, `"beam": 1`) turns every laser you
carry (main gun, Laser Emitter, off-hand) into a beam. It only shows up in shops after the meta unlock "reach
wave 5", and only while a laser is equipped. The Sustained Beam Emitter now requires the Lens, and the Lens can't be
sold while a Sustained Beam is installed. The other ammo (Bullets, Razor Blades, Shock Grapple) and frames (Blunderbuss, Long Rifle, Auto-Repeater) are found later:

- *In a run:* the shop sometimes offers a part that **swaps the main gun's ammo or frame** (`Run.PARTS`, built from
  `data/rules.json` `parts`). Each shop slot has a 25% chance (`parts.chance`) to be a part, at most one per shop,
  from the first shop on. A part can come up on its own tier or any higher rolled tier. Prices are wave-scaled like
  modules (+14% per wave):

  | Part | Tier | Base price | Wave-2 price |
  |---|---|---|---|
  | Bullets (ammo) | Common | 18 | 21 |
  | Razor Blades (ammo) | Rare | 28 | 32 |
  | Shock Grapple (ammo) | Rare | 34 | 39 |
  | Blunderbuss (frame) | Common | 22 | 25 |
  | Long Rifle (frame) | Common | 20 | 23 |
  | Auto-Repeater (frame) | Rare | 30 | 34 |
  | Laser / Ray Pistol | Common | 16 / 14 | only offered when the run started with a different part |

  These prices sit with the common/rare modules (12–38). A whole new firing style is worth about one good module,
  and a wave-1 income of 40–55 scrap can afford one. Parts never go into `build.items`. `build.ammo` / `build.frame`
  change, and `build.swapped[part]` marks the part as bought.
- *Swapping and selling:* the gun's ammo and frame are listed with the installed modules in the shop. A **bought**
  part sells for the usual 45% refund, and the run's **starting** part goes back on. Buying another part of
  the same kind **trades in** the bought one for that 45% refund, which counts towards the price (the card shows
  "Trade in X: −⚙ n" and the net price). A starting part can't be sold and is worth nothing as a trade-in. The run's
  current and starting parts are never offered. The automatic weapon name follows swaps unless you renamed it.
- *Across runs (Dead Cells-style):* going further unlocks parts as alternative **starting** picks in the Lab
  (`game/unlocks.gd`; rules in `data/rules.json` `unlocks`). Unlocks only add choices: each run still starts on Laser +
  Ray Pistol unless you pick otherwise.

  | Unlocks as a start | Requirement |
  |---|---|
  | Bullets | Reach wave 4 |
  | Blunderbuss | Defeat the wave-5 boss (Captain Ironclad) |
  | Long Rifle | Reach wave 8 |
  | Razor Blades | Defeat the wave-10 boss (Static Surge) |
  | Auto-Repeater | Defeat the wave-15 boss (Glacia) |
  | Shock Grapple | Reach wave 12 (rule added with the grapple work) |
  | *Focusing Lens* (shop module, not a start) | Reach wave 5 |

  Any difficulty counts. Wave progress is recorded when a wave starts (`main._start_wave`) and bosses when they die
  (`arena.gd`). A new unlock shows in the boss banner and on the game-over screen. The Lab shows locked parts
  greyed out with lock icons. Progress is
  saved to `user://unlocks.json` (`{"version", "best_wave", "bosses", "unlocked", "highest_difficulty", "heists"}`). A missing or damaged file
  starts a fresh profile. Test processes (`--script`, `--autoplay`, `--wave`) keep progress in memory and never
  write the player's save.

**Shock Grapple** (`game/grapple.gd`, ammo id `hook`). Instead of shots, the main gun fires an electrified
grappling hook. Hold RT / left mouse: the hook flies along the aim (hitting cops in its path for 1.2× damage) and
bites into the first wall, prop or arena edge it reaches. While fire is held the chain stays tight between the
muzzle and the anchor. The villain can keep moving, but no further than the chain's length from the anchor. Every
cop touching the chain takes 0.6× damage, with on-hit effects. Let go to reel it in. A hook that reaches full
length without biting reels in, and so does one whose chain gets a wall between the gun and the anchor (it snaps).
The frame sets the feel: **range** × 1.35 = chain length, **width** = how thick (easy to touch) the chain is, and
**fire rate** = how often each cop is shocked (half the frame's cooldown, 0.12–0.55 s). Extra guns from modules
still fire normally. The rear off-hand gun never takes grapple ammo, and Split Shot isn't offered with it. The gun
shows a chain reel on top and a claw in the muzzle that disappears while the hook is out. Tests:
`game/tests/grapple_test.gd`.

**Difficulty** (`ui/difficulty_screen.gd`, `Run.set_difficulty`) is picked once per run, like Brotato's danger
levels: Petty Crook, Nuisance, Menace, Supervillain, Arch-Nemesis. Each tier is one column of `Run.TIER`:
cop HP, cop damage, spawn rate, cop speed, payout per cop, and how many waves earlier the tougher cop types
unlock. See the tuning notes below for the table.

**Wave themes.** Each wave re-dresses the same arena with a palette, floor, props, lamps and
time of day: City Streets, Bank Lobby, Rooftop, Police HQ, Museum, Harbour and Spy HQ. Wave 1 is always the
street; the rest are shuffled per run (`Run.theme_for_wave`). A siren flash and a banner such as "WAVE 4 ·
ROOFTOP" open every wave. Cars and tanks are limited to streets and harbour. Six solid props per theme are obstacles that bullets,
lasers and razors respect. Cops path around them, and they keep the anti-wall-clip logic (`collide_walls(prev)`).

**Destructible scenery** (`game/scenery_damage.gd`). All six solid props take weapon and explosion damage:
cars 160 HP, desks 80, AC units 120, servers 140, cases 240, containers 360, stone pillars 600. Bullets leave
persistent holes, lasers leave heat scars, razors cut grooves, and impacts throw material-colored fragments.
Damage marks are capped at 32 per prop. Thermite ignites cars, wooden desks and server electronics; metal
containers, AC units, stone and glass scorch without catching fire. Burning cars detonate after 2.2 s;
explosion damage shortens the fuse to 0.8 s, and depleted car HP detonates immediately. Repeated hits cannot
delay a fuse. Car blasts deal 36 damage to nearby enemies and 12 to the player (before armor), reach 130 units,
and can ignite other cars. Enemy bullets and rockets also affect scenery. Destroyed props leave walkable
debris, lose their lights and shadows, and immediately open navigation; museum loot is preserved. Fire,
damage and wrecks reset with the next wave. Run `game/tests/scenery_test.gd` for regression coverage.

**Economy.** Cops drop scrap gears, civilians drop cash when hit (and escape at the edges), and plutonium crates
pay scrap and heal 15%. The magnet range is the pickup stat. Starting health is **30 HP**. Income is the
prototype's rate plus 10% (`data/rules.json` `economy.income_multiplier` = 1.1). In the **shop**, owned modules can be
**sold** for 45% of their current price: select one, then press A or click again to confirm. The Bionic
Arm can't be sold while a weapon or utility is mounted on it.

**Fire and poison spread.** Burning and poisoned cops can pass the effect on, like Sickness. Each second a burning
(or poisoned) cop has a `burnSpread` (or `poisonSpread`) chance to infect one cop within 70 px
(`enemy.gd` `_spread`). A caught fire burns for 2 s at 75% of the source's damage per second. Caught poison carries
half the stacks (min 1) for 4 s. Each catch is one generation further, and a cop that caught it second-hand
(generation 2) can't pass it on, so a crowd can't burn forever. A direct hit makes a fresh source (generation 0). The stats
start at 0. **Napalm Gel** (Common, 16: +40% fire spread/s, offered once you have Thermite) and **Toxic Spores**
(Common, 16: +40% poison spread/s, offered once you have a Toxin Vial) raise them, and stacks add up. The stat panel shows
both chances.

**Close-range rules** (fix for K9s that couldn't be killed once they reached you):
- *Point-blank hits:* any shot or beam also hits a cop pressed against the villain's body (within the villain's radius + the cop's
  radius + 8 px) on the side the shot goes (`Arena.touching_body`). Before, hits were measured only along the
  shoulder-to-barrel line, so a small dog sitting on or beside you was never hit.
- *No stacking:* melee chasers stop at your edge instead of walking onto your centre.
- *Bite knockback:* a contact hit pushes the biter back 26 px.
- *Speed cap:* ground melee cops (not drones, bosses or civilians) are capped at 92% of the villain's base speed (193)
  after wave, tier and ±20% scaling (`data/rules.json` `enemies.chaser_speed_cap`). A K9 used to roll up to ~300
  against your 210 and could not be outrun.

**Loot roll (Brotato-style).** Not every downed cop drops scrap. Each kill rolls `Run.drop_chance()`, which is
`economy.drop_chance` (65%) plus the `dropPct` stat, clamped to 5–100%. Bosses always drop, and civilian cash and
crates are separate. To keep the tuned economy, a drop is worth ×1/0.65, so average income at the base chance is
unchanged. Raising the chance is real extra income, and lowering it is a real cost. Modules that move it:
**Pickpocket Glove** (Common, 14: +12% drop chance) and **Overkill Charge** (Rare, 30: +4 damage, −15% drop
chance). The shop's stat panel shows the current "Loot drop" chance. Neither module draws on the character (art unchanged).

The **Bionic Arm is a purchased common upgrade**, not starting equipment. It automatically punches nearby
foes. Its one weapon slot can instead hold a gun firing opposite your main aim, Time Freeze (2.8 seconds,
15-second cooldown), or Proximity Bomb (radial blast, 12-second cooldown). Utility weapons replace the
arm's punch/rear gun. Hold main fire for both guns; LT/right mouse fires the rear gun or activates a utility.

**Manual melee and dual wielding.** The Lab's primary weapon list includes Switchblade, Mad Sword and
Shock Whip from the start. Sweep the right stick (or move the mouse around the scientist) to swing;
no trigger is needed. A fast sweep deals heavy damage, while holding the blade still deals none.
Gun frames apply to ranged primaries. The bionic arm's Switchblade, Mad Katana and Shock Whip remain
independent automatic secondary weapons, so a manual sword plus an auto sword is a supported build.
Melee upgrades improve both hands. Blade trails use the rendered blade's actual path and length,
stay at the location of the swing, then fade over 0.28 seconds. Walls block melee damage.
Controller menus use the left stick or D-pad to highlight a control; **A activates the highlighted box**.
**B** goes back from difficulty to weapon design (keeping the loadout), then from weapon design to the title.

Quick dual-sword tryout (does not save unlocks):
`Godot_console --path . -- --wave 1 --ammo katana --items bionic_arm,katana`.
`game/tests/melee_test.gd -- --screenshots` captures the dual-sword trails in `test-results/`.

**Ebola Ammo** is a Rare shop coating (32 base scrap). Weapon hits infect biological enemies for eight
seconds, dealing 4 damage/second per copy and slowing them. An enemy killed while infected leaves a
yellow-green infectious corpse: walking across the body infects another enemy, which can continue the
chain when it dies. The actual corpse owns the contact effect, so it ends with the body's fade and never
carries into the next wave. Normal, vaporized and shattered bodies are not infectious; robots, vehicles,
civilians and allies are immune. This works with primary and secondary melee as well as guns.

Lasers use a continuous capsule-masked shader with rounded ends. Chain upgrades add electric filaments,
burning adds a warm red-orange halo and local lighting, with frost/toxic/mind-control accents as equipped.
Defeat headlines rotate between BUSTED!, FOILED AGAIN!, CURSES!, and MEDDLING COPPERS!

The viewport is 960×540; the initial window is 1280×720. The game window is titled **The Diabolical Doctor**.

## Tuning notes

Balance pass, 2026-11-22. Measured with `game/tests/balance_probe.gd`, a headless kiting bot that plays real
waves. It is not a pass/fail suite:
`Godot_console --path . --audio-driver Dummy --headless --script res://game/tests/balance_probe.gd -- --waves 20 --diff 1,3,5`
(add `--item-probe --at 8` for a per-module impact table). Reference for feel: a Brotato run at Danger 5 had
short opening waves, one-hit kills on the first enemies, about 60 currency at the first shop, and items at 12–38.

**Feel and speed**
- Villain speed is 210 (was 150). Cop speeds are about 35–45% higher: cop 100, K9 185, detective 88, riot 66,
  drone 158, SWAT 125, hero 85, civilian 200. Per-wave speed growth is 1% (was 1.2%).
- Each cop rolls ±20% speed (was ±10%), so a crowd of one type spreads out instead of moving as a block.
- One-shot opener: cop HP is 5 (was 10) and Laser damage is 8 (was 7). The starting Laser Ray Pistol kills a
  wave-1 cop in one hit on every tier (6.5 HP on Arch-Nemesis). Other HP values: K9 4, detective 8, riot 30,
  drone 5, SWAT 18. Wave HP scaling is unchanged, so two-hit kills start around wave 2–3.

**Difficulty tiers** (`Run.TIER`; replaces the linear heat formulas)

| | Petty Crook | Nuisance | Menace | Supervillain | Arch-Nemesis |
|---|---|---|---|---|---|
| Cop HP | ×0.85 | ×1.0 | ×1.1 | ×1.2 | ×1.3 |
| Cop damage | ×0.6 | ×1.0 | ×1.25 | ×1.5 | ×1.7 |
| Spawn rate | ×0.75 | ×1.0 | ×1.25 | ×1.45 | ×1.6 |
| Cop speed | ×0.92 | ×1.0 | ×1.06 | ×1.11 | ×1.15 |
| Payout per cop | ×1.0 | ×1.0 | ×0.95 | ×0.92 | ×0.9 |
| Tough types unlock | — | — | 1 wave early | 2 early | 3 early |

Before, Arch-Nemesis was only +42% HP and +30% damage. It was also the richest tier, because more spawns meant more drops on
top of a +30% payout bonus. Spawn rate now scales the timer only, not group size as well, so ×1.6 really means
×1.6. In the probe, Petty Crook and Nuisance took almost no damage, Menace had trouble around boss waves, and
Arch-Nemesis "died" (HP refilled) in most waves after wave 3.

**Wave pacing** (`data/rules.json` `waves.len`, `arena.gd` `spawn_group`)
- Lengths: 30 / 35 / 40 / 45 / 50 / 55 s, then 60 s (were 40 / 50 / 60).
- Spawn timer: `max(0.5, 1.7 − 0.06·wave)` s (was `max(0.35, 2.1 − 0.09·wave)`). Group size is 1–3 plus
  1 per 4 waves (was 1–2 plus 1 per 2.5 waves, × spawn mult). Alive cap is `30 + 5·wave` (was `40 + 8·wave`).
  Wave 1 sees about 35 cops. Late waves peak around 20–40 alive for a strong build and about 140 on Arch-Nemesis.

**Economy**
- New `economy.kill_scrap_falloff` = 0.3: scrap per cop kill is ×1/(1 + 0.3·(wave−1)), so wave 10 pays 27%
  and wave 20 pays 15%. Kill counts grow about 15× over a run while prices only double, so before this the bot banked
  1,000–24,000 unspent scrap by mid-run. Crates, civilian cash and boss drops are unaffected.
- Civilian cash is `(5 + wave)·rich` (was `6 + 2·wave`). Plutonium crates pay `4 + wave` (was `4 + 2·wave`).
- Shop price growth is 14% per wave (was 11%). The sell refund stays at 45%.
- Result: about 40–55 scrap from wave 1, about 100–200 per wave by wave 5, and 300–1,200 per wave late. A bot
  that buys and rerolls holds about 0–100 between shops.

**Weapons and modules** (from the item probe: two copies of each module on a wave-8 build)
- Storm Generator chain damage +20% (was +40%).
- Grenade Clip and Mini Nuke Payload explosions deal `14 + 0.8·dmg` (was `30 + 0.6·dmg`). The flat 30 one-shot whole
  mid-game crowds; grenade dropped from 1.62× to 1.35× baseline kills.
- Time Bomb Dispenser: 8% time-bomb chance (was 15%), price 38 (was 32).
- Plague Drum: sickness 15% (was 25%), price 38 (was 30).
- Hive Mind Antenna: minions ×1.6 (was ×2).
- The top of the table is now the epics and legendaries (Storm Generator, Pocket Singularity, Moon Laser Uplink) at about 1.6–1.7×. The cheap rares
  no longer match them.

**Bosses** (`enemies.json`: hero base damage 14 (was 16); boss damage grows 6% per wave (`scaling.boss_dmg`;
was 12%); per-hero `hp` factor)
- HP factors: Captain Ironclad 0.85, Static Surge 0.75, Glacia 0.8, Omega Paragon 1.3. Before, bosses
  scaled `220 × wave HP × wave/5` with no per-hero factor. Paragon died in 4–6 s on wave 20 while Surge and Glacia
  outlasted their waves. Contact damage on wave 20 is now 18 / 37 / 51 (Petty / Menace / Arch) where it was 52 / 60 / 68,
  so one touch no longer wipes a 30–60 HP bar.

**Not changed:** controls, arena layout, art, the sell rate (45%), frame stats, and Bullets and Razor damage.

**Starting loadout** (later the same day): runs now always start on the Laser Ray Pistol that these numbers were tuned
around. The other ammo and frames are shop swaps or unlockable starts (see "Starting weapon, part swaps and unlocks"
above). `data/ammo.json`, `frames.json` and `items.json` are unchanged, so `character/art/gear.json` didn't need a re-sync.

## Controls

| Action | Keyboard / mouse | Controller |
|---|---|---|
| Move | WASD / arrows | Left stick |
| Aim | Mouse | Right stick |
| Main / off-hand fire | Left / right mouse | RT / LT |
| Phase dash (hold to sprint) | Shift | B |
| Use consumable | Q | X |
| Equipped ability | F | Y |
| Detonate mines | Space | LB / RB |
| Pause | Esc / P | Start |
| Select | Enter | A |
| Reroll in shop | R | Y |
| Mute | M | — |

## Procedural character

`character/` is self-contained and has no autoload dependency. Instantiate `character/villain.tscn`.
The Godot drawing code is now the art master; the root `villain.js`, `index.html`, `sprite-lab.html`,
and the old exported sheets remain as the browser prototype and reference material.
Exporting from Sprite Lab no longer updates the art used by the native rig.

- `art_renderer.gd`: body, palettes, gear, dynamically laid-out gun modules, hurt face, x-ray skeleton, and live effects.
- `pixel_canvas.gd`, `pixel_pen.gd`, `height_profiles.gd`: albedo/height rasterization, selective outlines,
  OpenGL normal maps, and pixel primitives shared by textures and live overlays.
- `villain.gd`: rig, animation, aim/recoil, anchors, both guns, lights, orb, reactions, and caching.
- `art/gear.json`: character-local snapshot of ammo, frame and item definitions. The tests check it against
  `data/` so the standalone character and gameplay stay in agreement.
- `game/villain_view.gd`: connects the run's build and combat state to the character.

All original items can change the body or weapon appearance. Modules stack into rails, the barrel grows
to fit them, and dense loadouts also expand their texture canvas. Mutagen, icy hair, coat stacks and all
four backpacks are drawn natively. Live effects include the telescope, hamster wheel, sparks, flames,
bubbles, rotating hardware, shout face, rocket jets, muzzle flashes, and the pose-following x-ray.

Frames and maps are cached across previews and gameplay. `prepare_for_play()` warms the walk, aim and
reaction variants on the wave transition so they do not need to be generated during combat.

```gdscript
villain.set_items(
    ["telescope", "core_battery", "scope", "boots"],
    "laser", "rifle",
    {"ammo": "bullet", "frame": "pistol", "items": ["cell"]}
)
villain.set_state({
    "aim": -0.2, "off_aim": -0.1,
    "moving": true, "walk_phase": 0.25,
    "recoil": 0.8, "flash": 0.06,
    "recoil2": 0.4, "flash2": 0.06,
    "firing": true, "firing2": true,
    "white": false, "zap": false
})
```

`ammo` and `frame` on the main build use string IDs. An off-hand spec accepts string IDs or table indices.
Pass `null` for the off-hand spec to use the purchased bionic fist, or the normal arm when that upgrade is unowned. State keys may be omitted; angles are world-space
radians, walk phase is one stride in 0..1, and recoil is 0..1.

`muzzle_global(gun_index)`, `shoulder_global()`, `off_muzzle_global()`, `off_shoulder_global()`, and
`anchor_global("head")` / `anchor_global("gun.muzzle")` return current world positions, including recoil.
`gun_offset(index)` gives stacked barrel spacing; `visual_bounds()` lets previews fit the current build.
Sprite anchors update immediately when state changes, before the game spawns shots.

`muzzle_global(gun_index, shot_index)` and `off_muzzle_global(shot_index)` can also select a particular
nozzle on a split-shot weapon. Stacked guns use their own barrel lengths and ammo-colored flashes.
Gameplay supplies optional `time` and `gun_flashes` state so animation, recoil, flashes and beam origins
share the same simulation step; standalone previews can keep using the rig's own clock.

## Gun effects and projectiles

Laser visuals follow the current animated nozzle through walking, turning, recoil and reactions.
Sustained beams reuse one ray per nozzle; pulse damage remains a single hit, independent of its fading
visual. Beam lifetimes preserve the first rendered frame, including at 20 FPS.

Bullets and razors spawn after recoil is applied, then travel independently. Tracers begin at the real
spawn point. Swept collisions handle enemies and thin walls in travel order; razors reflect at the actual
collision surface. A wall between shoulder and muzzle blocks emission from a long barrel.

Blasters emit small glowing sparks and hot impact bursts with ammo-colored local lighting. Visible
particles, impact flashes and their light budget are capped. Particle simulation runs outside drawing,
so rendering extra frames does not emit extra sparks.

## Visual inspection

Run `character/tests/showcase.tscn` with F6 for a six-build gallery covering gear, both facings, dual guns,
hurt and x-ray. Run `character/tests/light_test.tscn` for the movable-light bench:
mouse moves the light, wheel changes its height, LMB fires, A/D aim, W walks, RMB toggles the off-hand gun,
B toggles beam lights, and N changes ambient light.

## Validation

From PowerShell, run `./check.ps1`. It finds Godot on PATH, through `GODOT_PATH`, or in the user's
`Tools/Godot` directory. A path can also be supplied with `-GodotBinary`.

- Character tests compare 109 frozen browser cases: every item, all poses, ammo/frame combinations,
  repeated modules, mixed builds, normal maps, x-ray frames, and both weapons (763 image comparisons).
  Additional checks cover facing/recoil alignment, off-hand ammo colors, the eight-frame walk and dense builds.
- Gameplay tests compare the browser's build math, exercise every enemy/boss family, status effects,
  shop/purchases/rerolls, pause, game endings, and screen layout.
- Part-swap tests (`game/tests/swap_test.gd`) cover the Laser Ray Pistol start (still one-shots a wave-1 cop on
  every tier), part offers in `gen_offers`, buying, trade-in, selling back to the starting part, the shop cards
  and chips, the Focusing Lens shop rules, and the loot roll (drop chance, modifiers, observed rate and value,
  bosses always drop). The laser bolt vs. beam is checked in `game/tests/effects_test.gd`.
- Combat-rule tests (`game/tests/combat_rules_test.gd`) cover fire/poison spread (no spread without the stat,
  neighbour radius, 75% fire / half poison stacks, two-hop cap, fresh source on a direct hit), the spread modules'
  shop gating, the K9 speed cap on Arch-Nemesis wave 20, chasers not stacking on you, bite knockback, and
  point-blank hits on a dog at or around the villain's centre (bolt and beam). With the point-blank rule turned off, the K9 checks fail. Unlock tests (`game/tests/unlocks_test.gd`) cover the save round trip, damaged or missing saves, the
  unlock rules and hooks (wave start, boss kill), the Lab's locked/unlocked cards, and picking an unlocked start.
- Train heist tests (`game/tests/heist_test.gd`) cover the heist wave schedule, the train arena and camera
  limits, the connected cars (a navigation route from the caboose to the vault), boarding spawns, walking car by
  car to the vault, failing on timeout, one unlock per difficulty (all five, never twice), the save round trip,
  and each reward changing the gun sprite.
- Arena tests (`game/tests/arena_test.gd`) cover the single arena, wave lengths, all seven themes plus the train, the
  difficulty picker and multipliers, bosses on 5/10/15/20, scrap/cash/crate pickups and the magnet, and the
  Bionic Arm slot. Selling tests (`game/tests/sell_test.gd`) cover refunds, arm-slot consistency and the
  two-press controller flow.
- Gun-effect regressions exercise walking and turning in both directions at 60 and 20 FPS, pulse and
  sustained beams, all split/stacked/off-hand nozzles, recoil, tracers, swept collisions, piercing order,
  wall clipping, ricochets, particle expiry and lighting limits.

`game/tests/arena_test.gd -- --screenshots` renders every wave theme into `test-results/` with a display/GPU.
Under PowerShell 5.1, `check.ps1` can treat the harmless "ObjectDB instances were leaked" warning as a failure;
run a suite directly to confirm: `Godot_console --path . --audio-driver Dummy --headless --script res://game/tests/<suite>.gd`.
`./check.ps1 -Screenshots` also renders the game screens into `test-results/`. The script fails on runtime
errors as well as failed assertions. The frozen reference atlases are test-only and excluded from exports.

For an ordinary automated combat run:

```powershell
& $env:GODOT_PATH --path . -- --autoplay 20 --wave 10 --items scope,drill,offhand --shot test-results/combat.png
```

The main scene supports `--autoplay seconds`, `--wave number`, `--items comma,separated,ids`,
`--ammo index`, `--frame index` and `--shot path.png`. Screenshot runs need a display/GPU;
headless mode can run logic checks without screenshots.

## Export

The Windows Desktop preset includes JSON data and excludes tests. Install the matching Godot export
templates to export `build/TheDiabolicalDoctor.exe` from the editor. A resource pack can be built without templates:

```powershell
& $env:GODOT_PATH --headless --path . --export-pack "Windows Desktop" build/TheDiabolicalDoctor.pck
```

The resource pack has also been smoke-tested independently of the source directory.
