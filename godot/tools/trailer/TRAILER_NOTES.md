# The Diabolical Doctor: trailer notes

**Video:** `godot/build/trailer/TheDiabolicalDoctor-trailer.avi`. It's 1920×1080 at 30 fps, about 1:39 long, with the
song baked in. It's a clean plate: no HUD, no in-game pop-ups and no titles.

**Song:** "mashed with deep perfection" runs at about 146.7 BPM. One bar is 1.636 s, and the first beat lands at 0.09 s.
Every cut below sits on a bar line, so text that slams in on a cut lands on the beat. The trailer uses the
song from 0:00 to about 1:35, then fades the music out over the last two bars, 1:35 to 1:38.

**Matching the game's style:**
- **Title and caption font:** JetBrains Mono Bold, `godot/ui/fonts/JetBrainsMono-Bold.ttf`.
- **Title colour:** neon green `#b4ff3c` with a hard drop shadow in `#2d4a12`, offset about 4 px down and right.
  This is the in-game title look.
- **Accent colours:** gold `#ffd23c` for money and loot lines, red `#ff5a5a` for danger lines, white for plain lines.
- **Studio name:** Shantell Sans ExtraBold, `godot/ui/splash/ShantellSans-ExtraBold.ttf`. White with a thick black
  outline and a red `#d8261c` shadow, the same as the in-game logo.

## Shot list and text cards

| Time | Shot | Suggested on-screen text |
|---|---|---|
| 0:00.1 – 0:06.6 | AngryRatGames logo animation: the rat fights the ninjas, then a close-up of its angry face | **AngryRatGames**, popping in at about 0:04.3 when the face fills the frame. This is where the game puts it. Optional small line underneath, 0:05.0: "presents" |
| 0:06.6 – 0:13.2 | Night street, rain. The doctor strolls in; cops and detectives close in; he opens fire at 0:09.9 | 0:07.0: "THE POLICE HAVE YOU SURROUNDED." · 0:09.9, on the first shot: "GOOD." |
| 0:13.2 – 0:16.5 | Bank close-up: Auto-Repeater lasers down the red carpet | none, let the lasers breathe. Or 0:13.2: "BUILD A" |
| 0:16.5 – 0:23.0 | Gun build: a new part bolts onto the gun on every beat (16 parts) | 0:16.5: "DOOMSDAY WEAPON" · 0:19.8: "ONE PART AT A TIME" · 0:21.4: "(MOSTLY BY THEFT)", small |
| 0:23.0 – 0:29.5 | Shock Grapple: hook into a pillar, then the electrified chain zaps cops | 0:23.0: "GRAPPLE." · 0:26.3: "ELECTROCUTE." |
| 0:29.5 – 0:32.8 | Mad Katana sweeps through a crowd | 0:29.5: "SLICE." |
| 0:32.8 – 0:36.1 | Shock Whip lashes a whole line of cops | 0:32.8: "WHIP." |
| 0:36.1 – 0:42.6 | Shrink Ray turret: cops shrink, the doctor stomps them | 0:36.1: "SHRINK THEM." · 0:39.4: "STEP ON THEM." |
| 0:42.6 – 0:49.2 | Freeze Ray turret: cops freeze into ice blocks, the doctor kicks them into the crowd | 0:42.6: "FREEZE THEM." · 0:45.9: "KICK THEM." |
| 0:49.2 – 0:55.7 | Bank robbery: drop the key-holder (0:50.6), grab the key, the vault door opens (0:52.6) | 0:49.2: "ROB THE BANK." · 0:52.6, as the vault opens, in gold: "ONE VAULT. ONE PRIZE PER DIFFICULTY." |
| **0:55.7 – 0:59.0** | **The drop:** a Blunderbuss with split shots, explosions, chain lightning and plasma orbs in a full crowd | Hold the text: let the drop hit clean. Or one huge word at 0:55.7: "CHAOS." |
| 0:59.0 – 1:05.5 | Train heist: fight east through the train cars | 0:59.0: "HIJACK THE TRAIN." · 1:02.3: "REACH THE VAULT CAR." |
| 1:05.5 – 1:08.8 | Boss: Captain Ironclad (charge and slam) | 1:05.5: "CAPTAIN IRONCLAD" with a sub-line "unstoppable charge" |
| 1:08.8 – 1:12.1 | Boss: Static Surge (teleports, lightning) | 1:08.8: "STATIC SURGE" |
| 1:12.1 – 1:15.4 | Boss: Velvet Viper (homing missiles) | 1:12.1: "VELVET VIPER" |
| 1:15.4 – 1:18.6 | Boss: Glacia (ice shards) | 1:15.4: "GLACIA" · 1:17.0, smaller: "AND WORSE." |
| 1:18.6 – 1:23.5 | Late game at Police HQ: moon laser, plasma orbs, mind-controlled cops | 1:18.6: "100+ MODULES." · 1:21.1: "ENDLESS BUILDS." |
| 1:23.5 – 1:28.4 | Spy HQ: sustained laser beams sweeping a crowd | 1:23.5: "BECOME" · 1:25.2: "UNSTOPPABLE." |
| **1:28.4 – 1:35.0** | **Climax:** the final boss against a maxed-out gun, in a full crowd | Hold the text for the first bar, then 1:30.0: "20 WAVES." · 1:31.7: "5 DIFFICULTIES." · 1:33.4: "1 MAD SCIENTIST." |
| 1:35.0 – 1:38.3 | End card: the doctor and his fully loaded gun on the lab grid; music fades out | 1:35.0: **THE DIABOLICAL DOCTOR**, large, neon green, centred above the doctor · 1:36.6: "PLAY FREE ON ITCH.IO" or "WISHLIST NOW", plus your store link · Studio name, small, in the bottom corner |
| 1:38.3 – 1:39.0 | Black | none |

## Notes for the edit

- **Text safe area:** the top third of most gameplay shots is open floor. The doctor stays near the centre, slightly
  low on the zoomed shots. Captions read best top-centre or lower-third, clear of the doctor.
- **Drop and climax:** 0:55.7 and 1:28.4 are the two big moments. They're cut hard on the downbeat, so a white flash
  or a one-frame screen shake on those frames will sell them.
- **End card:** the doctor sits in the lower two-thirds of the frame, leaving the top third free for the title.
- **Longer cut:** the song runs to about 2:57. To use more of it, the edit can loop the 1:18.6 to 1:28.4 power
  section, or I can extend the shot list in `godot/tools/trailer/trailer.gd` and re-render.
- **Re-rendering:** see the header of `godot/tools/trailer/trailer.gd`. The render needs a temporary `override.cfg`
  with `window/stretch/mode="canvas_items"` and a 1920×1080 viewport and window override, otherwise the capture is
  960×540. Delete it afterwards.
