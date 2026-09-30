"""Makes Inconsolata Aantekening: Inconsolata set to Consolas's measure.

Text brought from OneNote is often set in Consolas, which few computers but
Windows have. Drawn in another monospaced face its lines broke elsewhere and
stood taller, and its first line sank: Noto Sans Mono is a tenth wider, a
sixth taller a line, and sets its baseline a quarter of its size lower. This
gives Inconsolata, the face drawn after Consolas, Consolas's measure:

* every cell as wide as Consolas's, 1126/2048 of the size, the room added
  to the right of each letter;
* its lines as high as Consolas's, and their baseline where OneNote sets
  Consolas's: its typographic ascent, 1521/2048, below half its line gap,
  350/2048, and its descent, 527/2048, above the other half.

Run with fontTools, from the folder holding Inconsolata-Regular.ttf and
Inconsolata-Bold.ttf (github.com/googlefonts/Inconsolata, fonts/ttf):

    python3 consolas_measure.py <that folder> app/aantekening/fonts
"""

import sys
from pathlib import Path

from fontTools.ttLib import TTFont

FAMILY = "Inconsolata Aantekening"
CONSOLAS_EM = 2048
CONSOLAS_ADVANCE = 1126
CONSOLAS_ASCENT = 1521 + 350 / 2
CONSOLAS_DESCENT = 527 + 350 / 2


def measured(source: Path, style: str, target: Path) -> None:
    font = TTFont(source)
    em = font["head"].unitsPerEm
    cell = 500  # Inconsolata's advance, in its units.
    wide = round(CONSOLAS_ADVANCE / CONSOLAS_EM * em)
    for name, (advance, left) in font["hmtx"].metrics.items():
        if advance:
            font["hmtx"].metrics[name] = (advance // cell * wide, left)
    font["hhea"].advanceWidthMax = max(a for a, _ in font["hmtx"].metrics.values())
    font["OS/2"].xAvgCharWidth = wide

    ascent = round(CONSOLAS_ASCENT / CONSOLAS_EM * em)
    descent = round(CONSOLAS_DESCENT / CONSOLAS_EM * em)
    font["hhea"].ascent = ascent
    font["hhea"].descent = -descent
    font["hhea"].lineGap = 0
    os2 = font["OS/2"]
    os2.sTypoAscender = ascent
    os2.sTypoDescender = -descent
    os2.sTypoLineGap = 0
    os2.fsSelection |= 1 << 7  # Use the typographic metrics.

    names = font["name"]
    full = f"{FAMILY} {style}" if style != "Regular" else FAMILY
    postscript = f"{FAMILY.replace(' ', '')}-{style}"
    renamed = {
        1: FAMILY,
        3: f"{postscript};measured after Consolas",
        4: full,
        6: postscript,
        16: FAMILY,
    }
    for record in names.names:
        if record.nameID in renamed:
            record.string = renamed[record.nameID]
    font.save(target / f"{postscript}.ttf")


if __name__ == "__main__":
    source, target = Path(sys.argv[1]), Path(sys.argv[2])
    for style in ("Regular", "Bold"):
        measured(source / f"Inconsolata-{style}.ttf", style, target)
