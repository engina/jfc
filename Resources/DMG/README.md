# DMG background

Place the final background at `Resources/DMG/background.png`.

The image must be a 660×400 PNG. The packaging script validates that size and
then produces a Finder window with:

- JFC centered at `(151, 199)` with a 128-point icon
- Applications centered at `(509, 199)` with a 128-point icon
- No toolbar, status bar, or path bar

Keep the two icon areas visually quiet. The background can place a drag arrow or
short instruction between them. When the background is absent, packaging falls
back to a plain but functional DMG.

Finder persists the styled layout in the image's root `.DS_Store`. Packaging
fails if that metadata file is not written; a successful `hdiutil` conversion
alone does not prove that Finder applied the background.
