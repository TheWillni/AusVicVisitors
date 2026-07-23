# AusVicVisitors

Illustration assets for [AvianVisitors](https://github.com/Twarner491/AvianVisitors), scoped to species observed in Victoria, Australia (eBird region `AU-VIC`).

- 398 species (796 illustrations: perched + flight pose for each), all generated and background-cut.
- Species list is BirdNET's global label set filtered against eBird's `AU-VIC` region checklist, including corrections for scientific-name taxonomy drift between BirdNET's label taxonomy and eBird's current one (e.g. recent genus splits like Spotted Dove, several raptors and shorebirds) - these would otherwise silently drop out of a naive filter.
- Every illustration has been through an automated blind-verification pass (independent species re-identification + anatomy/wing-count check against the target species) plus a manual visual review pass, with corrective notes applied and affected species regenerated - not just a quick skim.
- `frontend/dims.json` and `frontend/masks.json` are included for direct use in an AvianVisitors collage frontend.

These images aren't perfect - I've prioritized fixing the more common species first, so rarer ones are more likely to still have issues. If you spot a problem, please submit a PR with a fix.
