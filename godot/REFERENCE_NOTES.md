# Reference notes: Brotato Danger-5 clip (2026-11-22)

Notes taken from a 3-minute recording of a Brotato run (waves 1–4, Danger 5), used as a feel reference.
These are observations, not a spec. Mad Villain keeps its own art, names and systems.

## Pacing and feel
- Waves are short at first: about 20 s, 25 s, 30 s, 35 s. A big countdown sits top-centre under "WAVE N".
- The first enemies die in one hit from the starting weapon. Damage numbers pop on every hit, with crits in yellow.
- The player is clearly faster than the basic enemy and can kite through gaps.
- Enemies of the same type move at visibly different speeds, so crowds string out instead of moving as a block.
- The arena starts sparse (about 8–12 on screen in wave 1) and fills up by wave 4.
- Red X markers telegraph spawn points about a second before an enemy appears.

## Money
- About 40–60 currency by the end of wave 1. Shop items cost 12–38, so 2–3 buys are affordable.
- The total still on hand stays modest: about 60–90 between waves 1 and 3 and about 160 by wave 4.
  Money is almost always spent.
- A small "bag" counter under the currency stores uncollected pickups (wave-end leftovers) for the next wave.
- Reroll starts at 1 and climbs by about 1 per wave.

## UI layout worth borrowing (ideas only, not changed in this pass)
- **HUD:** an HP bar with a level bar under it at top-left, currency below them, and wave number and countdown
  top-centre. The HUD is minimal: nothing else on screen during combat.
- **Shop:** 4 item cards across the top-left. Each card shows the icon, name, a type tag (Item / Weapon,
  rarity colour) and green/red stat lines. Under each card are a big price button, a Lock toggle and a Ban
  button.
- **Shop:** a permanent **Stats** panel on the right (Primary/Secondary tabs) lists every stat, with changed
  values coloured green or red. Mad Villain's shop has no stat sheet, so this is the biggest gap.
- **Shop:** owned Items and Weapons (n/6) sit in grids at the bottom, and "Go (Wave N)" is at bottom-right
  with the next enemy types previewed above it.
- **Level-up and found-item screens** reuse the card layout: Take / Recycle (+currency) / Ban.
- **Controller:** the face-button glyphs (X Lock, Y Reroll) appear right on the buttons.

## Applied in the balance pass
Shorter opening waves, a one-shot opener, a faster villain and faster cops, ±20% per-cop speed jitter, and a
tighter economy. See the README "Tuning notes".
