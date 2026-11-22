# The Diabolical Doctor — ideas backlog

Not built yet. Ideas from the 2026-11-22 brainstorm, with notes on where each would fit in the current game.
Every new item still needs a visible change on the villain and/or the weapon (see the design rules).

## Off-hand weapons (LT)

These would go on the off-hand, which already fires with LT / right mouse (Bionic Weapon Mount, `offhand` in
`data/items.json`). Most are close-range, so the off-hand becomes the panic button and the main gun stays ranged.

| Idea | How it could play | Visual |
|---|---|---|
| Samurai sword | Quick arc slash in the aim direction. Can block bullets during the swing. | Katana in the off hand; sheath on the back |
| Knife | Very fast stabs, short reach. Adds bleed. | Combat knife; knives on a belt |
| Whip | Long, thin arc that can pull a cop toward you or stun it | Coiled whip on the hip |
| Acid throw | Lobbed flask that leaves an acid puddle (chem burn over time) | Green flasks on a bandolier; glove stained green |
| Repulsion shock wave | Ring around the villain that knocks every nearby cop back. Long cooldown. | Glowing coil on the chest or back |
| Radiation ray | Thin, constant beam that makes cops sick and builds damage the longer it stays on one | Glowing green emitter; hazard stripes |

## Main weapons (RT)

The main gun is ammo + frame today. Melee weapons don't fit that, so they may need a new **weapon class** that
replaces the gun instead of being an ammo or frame swap.

| Idea | Type | How it could play |
|---|---|---|
| Chainsaw | Melee class | Hold RT to rev; constant damage to whatever it touches. Slows you while running. |
| Samurai sword (dual wield?) | Melee class | Combo slashes. Dual wield could take both RT and LT, or need a second sword bought. |
| Goo gun | Ammo | Sticky blobs that slow cops and stick them together |
| Heat ray | Ammo | Constant beam; damage climbs while held on a target; adds burn |
| Flame thrower | Frame or ammo | Short cone, burn, can't go through walls |
| Grenade launcher | Frame | Arcing shots that explode on landing. Separate from the Grenade Clip item, which is a chance on hit. |
| ~~Electrified grappling hook~~ **Built** as the Shock Grapple ammo (see README) | Special | **Hold RT** to fire the hook. It sticks to a wall or object and the chain stays tight between the villain and the anchor. The villain can keep moving, and any cop touching the chain takes shock damage. Let go of RT to release. |

Open questions:
- The samurai sword is on both lists. Off-hand only, main weapon only, or both (dual wield = one in each hand)?
- Grappling hook (built): the chain snaps if a wall comes between gun and anchor, and stops the villain at full
  length. Possible upgrades: chain bends around corners, reel the villain in to the anchor, stronger shocks.

## Power-ups

- **Jet pack on B** (preferred over a plain dodge): the scientist blasts straight up, out of reach. While airborne
  they can't be hit and can steer to a safe spot, then land. Drawn as a jet pack on the villain's back, with a
  shadow on the ground marking where they'll come down.
  - **Upgrade: Crash landing.** Landing slams down and deals area damage around the landing spot, so the jet pack
    turns into an attack.
  - Other upgrade options: shorter cooldown, longer air time, a burn trail from the exhaust on take-off.
- ~~Dodge on B~~: a short dash with invincibility. Replaced by the jet pack idea above.

## Allies

- **Drone assistants** (like Brotato's turrets/drones): small robots that orbit or follow the villain and attack on
  their own. They can fire automatically because they are not the player's gun; the no-autofire rule is only for
  the villain's own weapons. Kinds could match the ammo types (laser drone, saw drone, healer drone). Shown as
  drones flying around the villain, plus a remote or antenna on the villain.
