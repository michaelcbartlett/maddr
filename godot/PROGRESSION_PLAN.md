# Game progression plan

The campaign begins with a mission, reveals the clone lab after the first death, and uses repeated runs to move from villainous ambition toward bringing back the doctor's lost lover. The rainy street remains the opening mission. The lab becomes the place for preparation, trophies, changing dialogue and departure by teleporter.

## Starting a game

A basic title screen leads to four independent game slots. A fresh slot starts the first mission with the existing Laser and Ray Pistol. Weapon design and difficulty selection belong after the first mission, through the lab rather than before the opening. Save selection must not reveal the cloning twist.

The doctor teleports onto the map in a vertical green beam, inspired by Mega Man. He never walks there from the lab; the police must not learn where the lab is. The current first implementation can use the existing scientist rig, a beam, materialization and a brief input lock. More elaborate arrival details can be added after the timing works.

## Hybrid mission formats

The campaign will mix horizontally scrolling stages, connected room maps and dedicated boss arenas. Keep the current 2.5D perspective, twin-stick movement and aiming, combat rules and character rig consistent across all three. Change the level layout, camera boundaries and encounter pacing to suit the location.

| Format | Locations | Purpose |
|---|---|---|
| Streets of Rage inspired scrolling | Streets, trains, bridges and escape routes | A wide, shallow walkable floor with horizontal camera progression, ambushes and fights toward a destination. Preserve movement through the floor's depth. |
| Binding of Isaac inspired room maps | Banks, laboratories, museums and police headquarters | Connected rooms, branching routes, optional loot, keys and security objectives. Extra rewards can cost another fight and more health. |
| Boss arenas | Vaults, rooftops and superhero confrontations | Deliberate combat spaces with room to read attacks, maneuver and finish the mission. |

Use the format that serves each location. Some missions can use a single format; others can link several formats within one heist. Health, weapon build, carried supplies and upgrades persist across a mission's transitions.

The first prototype is **teleport onto the rainy street → fight through police-car barricades toward the bank → explore three to five connected rooms with an optional branch → reach a vault boss arena**. This gives the transitions a small, playable test before expanding the campaign.

Reuse the long train stage and existing bank objective as foundations. New work includes room connections and clear conditions, camera boundaries, transition handling and encounters balanced for each space. Introduce exploration pauses between fights rather than applying a continuous survival-wave timer to every section. Keep exact room counts and mission lengths adjustable after playtesting.

### Opening street stage

The first stage is a horizontally scrolling street with walkable depth, using the existing 2.5D perspective and twin-stick controls. The doctor teleports into the street and advances along the road toward the next location.

Some police encounters form roadblocks with police-car barricades. The player must get through these barricades to continue along the route. Their collision and layout must make them actual obstacles rather than decorative parked cars. The exact method of clearing each barricade, its durability and the police deployment remain to be designed.

Parallax city scenery frames both the **top and bottom of the screen**, with the playable street between them. Upper city layers and lower foreground layers scroll at different rates to give the route depth. Keep the road, enemies, projectiles and barricade openings readable as the camera progresses; foreground scenery must leave the combat area visible.

Retain rain, sparse puddles, streetlights and applicable sprite/light reflections as the street's visual foundation. Stage advancement and barricade encounters replace the current opening's stationary survival-wave structure.

## Death and the lab

The first death cuts from the street to silence/black, without an arrest or conventional game-over screen. The player wakes through the doctor's eyes: two black eyelids open on blurred green, blink, look around and focus. A cat is looking through the vat glass. A wider shot reveals the vat and other vats, followed by a quick black transition to the doctor standing in his lab coat, ready to control.

The first wake-up is approximately 12 seconds and skippable. Later deaths use a short version of roughly two seconds, with lines that can reflect the cause of death. Run statistics can move onto a lab monitor instead of interrupting the return.

The lab is a walkable room. The player approaches objects and interacts to see short inner-monologue popups. It includes evil cats, clone vats, trophies from earlier jobs, a wanted poster, a heist board and a phone. Objects and their lines change with deaths and accomplishments. Weapon preparation opens from a workbench; the teleporter starts the next mission.

Keep the cold and uncanny familiarity from the opening prose, with a vain, annoyed, funny doctor inside an unsettling room. A secret, enclosed lab and a vat fit this premise better than the draft's city-view windows and operating bench. “Dr. Aris Thorne” remains a provisional name.

## Successive campaign goals

The working order is a ladder of endings, with the lover's resurrection as the final emotional ending. Completing a goal creates a reason for another run.

| Order | Goal | Direction and replay reward |
|---|---|---|
| 1 | Steal the crystal | Gain the power source for an ultimate weapon. The weapon becomes purchasable on later runs. Power does not fix the empty lab. |
| 2 | Defeat the arch-nemesis superhero | Pursue revenge. The proposed reveal is that the hero recognizes previous loops. Hero equipment can become a trophy and wearable reward. |
| 3 | Steal the moon | The most extravagant, comic expression of his ego. Foreshadow it with an empty pedestal and “Soon.” The moon becomes a lab trophy. |
| Final | Bring back the lost lover | Resolve the real motive behind the earlier goals. The final vat wake-up mirrors the doctor's first death, through the lover's eyes, with him looking in through the glass. |

The proposed personal history links the hero to the lover's death. Cloning himself is possible because his memories were recorded; reproducing the lover's face does not restore the person without their memories. Recurring phone calls can become a puzzle in which the player learns the right response across runs, eventually recovering the missing record.

The suggested final sacrifice is enough power for one last rebirth: his or theirs. Giving up his own return would make the final run uniquely consequential. This sacrifice, the precise phone-call puzzle, the hero's connection to the loss and post-finale replay still need their final gameplay rules.

## Her face throughout the city

Billboards, advertisements and public-facing screens are the main recurring image. Early runs make her seem to be an ordinary celebrity: perfume ads, bus stops and toothpaste billboards. Later she advertises increasingly unlikely things, and slogans become personal, such as “You're late again,” “Call me” and “Still you?” Her face eventually reaches police recruitment posters and signs that appear to watch him.

The phone/hostage thread connects that familiar face to the lost lover. Slogans may hint at the response the player is trying to learn. Rain and puddle reflections carry the signs' presence into the street.

The plan favors the pervasive advertising motif over routinely giving every female NPC the same face. A rare encounter in which he sees her in an actual person remains a possible extension. Any forced hesitation that overrides shooting is a separate gameplay decision, not a requirement of this motif.

## The single perception break

The one-time break occurs during a death wake-up, replacing the earlier blackout/transformer proposal.

As the billboard imagery grows stranger, the player becomes accustomed to seeing her on a screen opposite the vat whenever the doctor's eyelids open. Once, midway through progression:

1. The lids open onto familiar blurry green.
2. Focus reveals an ordinary advertisement with a stranger's face.
3. He blinks, and the stranger is still there.
4. A slower second blink restores the lover's face.
5. The usual black transition returns him to the lab. He says nothing immediately.

The intended cause is that a new clone's eyes work before the copied memories finish loading. For an instant he sees the real world, then his perception returns. The cat gains the line, “You saw it too, didn't you.”

Persist a flag so this scene happens exactly once per game slot, even after a death, reload or replay. The working direction makes this particular short wake-up unskippable and only about two seconds longer than the normal short version. Do not add a second reveal through a lab security monitor, torn billboard or street blackout.

After the final ending, ordinary advertisements and distinct strangers return permanently. That is the resolution of the distortion. The lover's final wake-up shows the doctor clearly through their eyes, completing the visual reversal.

## Rules still to settle

The proposed teleporter limits are open sky for arrival and a traceable return beam that makes escape to the lab dangerous. These explain landing outside protected targets and returning through death, but successful mission extraction still needs a consistent rule. Do not make “death is the only way home” an absolute that contradicts successful heists.

Final character names, exact campaign lengths, ending unlock conditions, the lover's identity, the resurrection cost and post-finale replay remain design choices. The existing five-wave street prototype and preserved 20-wave combat rules are development structures, not a locked campaign layout.

## Implementation order

1. Basic title and four save slots, followed by the teleport arrival into the existing map.
2. First death to black, eyelids and a placeholder lab return, replacing the arrest screen.
3. Walkable placeholder lab with four interactables, short monologue popups and teleporter departure.
4. Persistent per-slot deaths, causes, dialogue history, goals, trophies and the once-only wake-up flag.
5. Prototype the hybrid street-to-bank mission: a scrolling street with police-car barricades and upper/lower parallax city scenery, connected interior rooms and a vault boss arena, sharing one build and control scheme.
6. Crystal objective and reward, then the later endings and evolving advertisement imagery. Expand mission formats after the first hybrid route plays well.

Current scope starts with menus, isolated slot progression and teleport arrival. Clone wake-ups, the walkable lab, hybrid missions, billboards and campaign endings require later work.
