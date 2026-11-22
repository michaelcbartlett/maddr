# Frozen browser references

These atlases were captured from the original root `villain.js` using the real `index.html` data and
an HTML Canvas-compatible renderer, before making Godot the character art master.
`cases.json` records loadouts, pose/weapon state, anchors, muzzles, gun rows, and original build math.
Each sheet uses eight columns; each cell is 62×70 (body/x-ray) or 232×98 (weapon).

`art_test.gd` compares native images with a maximum two-value color tolerance and one-value alpha
tolerance for HSL/alpha rounding. The current port differs by at most one color value.
Gameplay stats use numeric comparison so JSON float/int representation does not create false failures.
The dense-build test goes beyond the original fixed canvas and verifies that native weapons grow to fit.

These are regression fixtures, not runtime sprite sheets. Intentionally changing the native art may
require updating the affected reference cells after visual review. Do not regenerate them automatically
from the implementation under test.
