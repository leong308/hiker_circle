from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent / "render"
THUMB_WIDTH = 300
MARGIN = 18
LABEL_HEIGHT = 28
COLS = 2


for report_dir in sorted(path for path in ROOT.iterdir() if path.is_dir()):
    pages = sorted(report_dir.glob("page-*.png"))
    thumbs = []
    for page in pages:
        with Image.open(page) as source:
            ratio = THUMB_WIDTH / source.width
            thumb = source.convert("RGB").resize(
                (THUMB_WIDTH, round(source.height * ratio)), Image.Resampling.LANCZOS
            )
        thumbs.append((page.name, thumb))

    cell_height = max(image.height for _, image in thumbs) + LABEL_HEIGHT
    rows = (len(thumbs) + COLS - 1) // COLS
    sheet = Image.new(
        "RGB",
        (
            MARGIN + COLS * (THUMB_WIDTH + MARGIN),
            MARGIN + rows * (cell_height + MARGIN),
        ),
        "#d9dde1",
    )
    draw = ImageDraw.Draw(sheet)
    for index, (name, thumb) in enumerate(thumbs):
        column = index % COLS
        row = index // COLS
        x = MARGIN + column * (THUMB_WIDTH + MARGIN)
        y = MARGIN + row * (cell_height + MARGIN)
        draw.text((x, y), name, fill="#1f2933")
        sheet.paste(thumb, (x, y + LABEL_HEIGHT))

    output = ROOT / f"{report_dir.name}_contact.png"
    sheet.save(output, optimize=True)
    print(output)
