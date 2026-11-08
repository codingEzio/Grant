"""QA only: bounded, numbered contact sheets. Supply Python with Pillow."""
import json
import sys
from pathlib import Path

try:
    import PIL
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    raise SystemExit("Contact sheets require Python with Pillow; use the existing workspace runtime. No dependency is installed automatically.")

root = Path(sys.argv[1])
source_names = json.loads((root / "render.json").read_text())["files"]
extra = lambda name: name.endswith("-system.png") or name.endswith("-host-layout.png") or "fallback" in name or "appearance-font" in name or "inherited-font" in name
names = [n for n in source_names if not extra(n)] + [n for n in source_names if extra(n)]
images = [Image.open(root / name).convert("RGBA") for name in names]
font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 20)
margin, label = 24, 44
mapping, boards = [], []
for page, start in enumerate(range(0, len(images), 6), 1):
    batch = images[start:start + 6]
    width = max(im.width for im in batch)
    height = max(im.height for im in batch)
    rows = (len(batch) + 1) // 2
    sheet = Image.new("RGB", (margin * 3 + width * 2, margin * (rows + 1) + (height + label) * rows), (230, 230, 226))
    draw = ImageDraw.Draw(sheet)
    board = f"contact-sheet-{page:02d}.png"
    for local, image in enumerate(batch):
        index = start + local
        x = margin + (local % 2) * (width + margin)
        y = margin + (local // 2) * (height + label + margin)
        draw.text((x, y + 8), f"{index + 1:02d}  {names[index][:-4]}", font=font, fill=(35, 35, 35))
        sheet.paste(image, (x, y + label), image)
        mapping.append({"number": index + 1, "source": names[index], "board": board, "pixelSize": list(image.size)})
    sheet.save(root / board)
    if page == 1:
        sheet.save(root / "contact-sheet.png")
    boards.append(board)
(root / "contact-map.json").write_text(json.dumps(mapping, indent=2) + "\n")
(root / "contact-environment.json").write_text(json.dumps({"python": sys.version, "pillow": PIL.__version__, "scope": "QA only; maximum six sources per board", "boards": boards}, indent=2) + "\n")
print(f"Contact sheets: {len(boards)} boards, {len(images)} numbered sources; Pillow {PIL.__version__}")
