# Street vehicle assets

Seven transparent eight-direction sheets (56 views), made with the built-in imagegen tool using
the supplied elevated-camera reference. Every side-facing view keeps the roof visible.

- `delorean`: stock silver DMC-12, closed gullwing doors.
- `grand-wagoneer`: forest-green 1980s Jeep with wood panels.
- `boxy-sedan`: burgundy 1980s four-door sedan.
- `compact-hatchback`: mustard-yellow compact.
- `cargo-van`: cream enclosed van.
- `pickup`: faded blue single-cab pickup, empty open bed.
- `police-sedan`: black-and-white 1980s patrol sedan, live red/blue roof bar.

`catalog.json` and each model's `views.json` describe image regions, scale and the police lens
anchors. View names describe the visible end of the vehicle: `front` points down-screen, `rear`
points up-screen, and `left`/`right` name the direction of the nose. The diagonal views are retained
for future use; curb parking uses the four road-aligned directions.

Police `bulbs` are the measured centers of the painted red/blue glass components. Per-view
`lens_regions` and cached runtime alpha masks restrict each flash to that glass, including its
slanted outline. Flash sprites share the body sprite's source origin and scale, rather than a
generic rotated rectangle. Normal-map lighting and puddle emissions use the same measured centers.

The generated masters keep their original RGBA pixels. `tools/vehicles/package_sheets.py` copies
masters and detects region bounds; it does not resample or repaint them. Sprite regions exclude
unrelated stray alpha outside the vehicle bounds. The sedan uses the cleaned second generation.
`generation-prompts.json` records the generation specifications and background cleanup request.

Runtime: `levels/parked_vehicle.gd`. Placement: `levels/rainy_street.gd::parking_layout`.
The opening selects 16–20 solid parked vehicles, all seven models and at least two cruisers. Police
lenses, light emission and reflected lamp sprites follow the same staggered double-flash clock.
