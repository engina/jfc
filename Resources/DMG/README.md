# DMG background

Place the final background at `Resources/DMG/background.png`.

The image must be a 660×400 PNG. The packaging script validates that size and
then produces a Finder window with:

- JFC centered at `(170, 205)` with a 128-point icon
- Applications centered at `(490, 205)` with a 128-point icon
- No toolbar, status bar, or path bar

Keep the two icon areas visually quiet. The background can place a drag arrow or
short instruction between them. When the background is absent, packaging falls
back to a plain but functional DMG.
