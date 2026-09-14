import json
import math
import os
import re
import sys
import urllib.parse
import urllib.request
from collections import Counter
from pathlib import Path

from PIL import Image, ImageDraw
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import (
    BaseDocTemplate,
    Flowable,
    Frame,
    Image as RLImage,
    KeepTogether,
    PageBreak,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)


ROOT = Path(__file__).resolve().parents[1]
AUDIT_PATH = ROOT / "tmp" / "trail_hazard_audit.json"
TRAIL_INPUT_PATH = ROOT / "tmp" / "trail_hazard_audit_input.json"
ICON_DIR = ROOT / "tmp" / "pdfs" / "hazard-icons"
MAP_DIR = ROOT / "tmp" / "pdfs" / "trail-map-previews"
OUTPUT_PATH = ROOT / "output" / "pdf" / "trail-map-caution-reference.pdf"

PAGE_W, PAGE_H = A4
GREEN = colors.HexColor("#39C66D")
DARK_GREEN = colors.HexColor("#0B2115")
INK = colors.HexColor("#142219")
MUTED = colors.HexColor("#637168")
PALE = colors.HexColor("#EAF8EF")
LINE = colors.HexColor("#D8E8DE")
AMBER = colors.HexColor("#F4B740")
RED = colors.HexColor("#E85D5D")

LABELS = {
    "river": "Water crossing",
    "stream": "Stream crossing",
    "bridge_crossing": "Bridge",
    "cliff": "Cliff",
    "ford_crossing": "River ford",
    "stepping_stones": "Stepping stones",
    "steep_ascent": "Steep ascent",
    "steep_descent": "Steep descent",
    "rope_assisted_section": "Rope-assisted",
    "ladder_section": "Ladder",
    "scrambling_section": "Scrambling",
    "loose_rock": "Loose rock / scree",
    "muddy_surface": "Muddy surface",
    "rough_surface": "Rough surface",
}

ICON_FILES = {
    "stream": "river.png",
    **{key: f"{key}.png" for key in LABELS if key != "stream"},
}


def read_mapbox_token():
    env = (ROOT / ".env").read_text(encoding="utf-8")
    match = re.search(r"^MAPBOX_ACCESS_TOKEN\s*=\s*([^\r\n]+)", env, re.M)
    if not match:
        raise RuntimeError("MAPBOX_ACCESS_TOKEN is missing from .env")
    return match.group(1).strip().strip("'\"")


def decode_polyline(value):
    points = []
    index = lat = lon = 0
    while index < len(value):
        for axis in range(2):
            result = shift = 0
            while True:
                byte = ord(value[index]) - 63
                index += 1
                result |= (byte & 0x1F) << shift
                shift += 5
                if byte < 0x20:
                    break
            delta = ~(result >> 1) if result & 1 else result >> 1
            if axis == 0:
                lat += delta
            else:
                lon += delta
        points.append((lat / 1e5, lon / 1e5))
    return points


def mercator(lat, lon):
    lat = max(-85.05112878, min(85.05112878, lat))
    x = (lon + 180.0) / 360.0
    sin_lat = math.sin(math.radians(lat))
    y = 0.5 - math.log((1 + sin_lat) / (1 - sin_lat)) / (4 * math.pi)
    return x, y


def map_view(points, width=1200, height=600, padding=90):
    projected = [mercator(lat, lon) for lat, lon in points]
    min_x = min(x for x, _ in projected)
    max_x = max(x for x, _ in projected)
    min_y = min(y for _, y in projected)
    max_y = max(y for _, y in projected)
    span_x = max(max_x - min_x, 1e-7)
    span_y = max(max_y - min_y, 1e-7)
    zoom_x = math.log2((width - padding * 2) / (256 * span_x))
    zoom_y = math.log2((height - padding * 2) / (256 * span_y))
    zoom = max(5.0, min(17.0, min(zoom_x, zoom_y)))
    return (min_x + max_x) / 2, (min_y + max_y) / 2, zoom


def lon_from_x(x):
    return x * 360.0 - 180.0


def lat_from_y(y):
    n = math.pi - 2 * math.pi * y
    return math.degrees(math.atan(math.sinh(n)))


def point_pixel(lat, lon, center_x, center_y, zoom, width=1200, height=600):
    x, y = mercator(lat, lon)
    scale = 256 * (2**zoom) * 2
    return (
        width / 2 + (x - center_x) * scale,
        height / 2 + (y - center_y) * scale,
    )


def placeholder_map(path, width=1200, height=600):
    image = Image.new("RGB", (width, height), "#E7F1E9")
    draw = ImageDraw.Draw(image)
    for offset in range(-height, width, 110):
        draw.line((offset, 0, offset + height, height), fill="#D1E5D6", width=4)
    draw.text((30, 30), "Map preview unavailable", fill="#52685A")
    image.save(path)
    return image


def make_map_preview(trail, audit, token):
    MAP_DIR.mkdir(parents=True, exist_ok=True)
    output = MAP_DIR / f"{trail['trailId']}.png"
    route = decode_polyline(trail.get("routeEncodedPolyline", ""))
    if len(route) < 2:
        route = [(trail["latitude"], trail["longitude"])]
    hazard_points = [
        (item["latitude"], item["longitude"])
        for item in audit.get("hazards", [])
    ]
    fit_points = route + hazard_points
    center_x, center_y, zoom = map_view(fit_points)
    lon = lon_from_x(center_x)
    lat = lat_from_y(center_y)
    url = (
        "https://api.mapbox.com/styles/v1/mapbox/outdoors-v12/static/"
        f"{lon:.6f},{lat:.6f},{zoom:.2f},0/600x300@2x"
        f"?access_token={urllib.parse.quote(token)}&logo=false&attribution=false"
    )
    try:
        request = urllib.request.Request(url, headers={"User-Agent": "HikerCircle-Audit/1.0"})
        with urllib.request.urlopen(request, timeout=25) as response:
            output.write_bytes(response.read())
        image = Image.open(output).convert("RGBA")
    except Exception as error:
        print(f"Mapbox preview failed for {trail['name']}: {error}")
        image = placeholder_map(output).convert("RGBA")

    draw = ImageDraw.Draw(image)
    route_pixels = [
        point_pixel(lat_value, lon_value, center_x, center_y, zoom)
        for lat_value, lon_value in route
    ]
    if len(route_pixels) > 1:
        draw.line(route_pixels, fill="#FFFFFF", width=16, joint="curve")
        draw.line(route_pixels, fill="#27B765", width=9, joint="curve")

    icon_size = 32 if len(audit.get("hazards", [])) > 24 else 46
    for hazard in audit.get("hazards", []):
        icon_name = ICON_FILES.get(hazard["type"], "river.png")
        icon_path = ICON_DIR / icon_name
        if not icon_path.exists():
            continue
        icon = Image.open(icon_path).convert("RGBA")
        icon.thumbnail((icon_size, icon_size), Image.Resampling.LANCZOS)
        x, y = point_pixel(
            hazard["latitude"], hazard["longitude"], center_x, center_y, zoom
        )
        image.alpha_composite(icon, (round(x - icon.width / 2), round(y - icon.height)))

    image.convert("RGB").save(output, quality=92)
    return output


def icon_cell(hazard_type, size=9 * mm):
    path = ICON_DIR / ICON_FILES[hazard_type]
    return RLImage(str(path), width=size, height=size)


class FooterCanvas(Flowable):
    def draw(self):
        return


def on_page(canvas, doc):
    canvas.saveState()
    canvas.setFillColor(DARK_GREEN)
    canvas.rect(0, PAGE_H - 11 * mm, PAGE_W, 11 * mm, stroke=0, fill=1)
    canvas.setFillColor(colors.white)
    canvas.setFont("Helvetica-Bold", 8)
    canvas.drawString(15 * mm, PAGE_H - 7.3 * mm, "HIKERCIRCLE  /  TRAIL CAUTION REFERENCE")
    canvas.setFillColor(MUTED)
    canvas.setFont("Helvetica", 7.5)
    canvas.drawString(15 * mm, 8 * mm, "Mapbox display | OSM and elevation enrichment | Advisory data")
    canvas.drawRightString(PAGE_W - 15 * mm, 8 * mm, f"{doc.page}")
    canvas.restoreState()


def summary_chips(counts, styles):
    if not counts:
        return Paragraph("No mapped caution matched the implemented rules", styles["small_muted"])
    cells = []
    for hazard_type, count in sorted(counts.items(), key=lambda item: (-item[1], item[0])):
        label = LABELS.get(hazard_type, hazard_type.replace("_", " ").title())
        cells.append(
            Table(
                [[icon_cell(hazard_type, 6 * mm), Paragraph(f"<b>{count}</b> {label}", styles["chip"]) ]],
                colWidths=[7 * mm, None],
                style=TableStyle([
                    ("BACKGROUND", (0, 0), (-1, -1), PALE),
                    ("BOX", (0, 0), (-1, -1), 0.5, LINE),
                    ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                    ("LEFTPADDING", (0, 0), (-1, -1), 3),
                    ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                    ("TOPPADDING", (0, 0), (-1, -1), 3),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
                ]),
            )
        )
    rows = [cells[index : index + 3] for index in range(0, len(cells), 3)]
    while rows and len(rows[-1]) < 3:
        rows[-1].append("")
    return Table(rows, colWidths=[58 * mm] * 3, hAlign="LEFT", style=TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 3),
        ("TOPPADDING", (0, 0), (-1, -1), 2),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
    ]))


def trail_block(trail, audit, map_path, index, styles):
    counts = audit.get("counts", {})
    total = audit.get("total", 0)
    if total:
        conclusion = (
            f"{total} mapped caution{'s' if total != 1 else ''} matched this saved route. "
            "Review the pinned sections before departure and again on the live Mapbox route."
        )
    else:
        conclusion = (
            "No mapped caution matched the current route under these rules. "
            "This does not prove that the trail is hazard-free."
        )
    title = Table(
        [[
            Paragraph(f"<b>{index:02d}</b>", styles["number"]),
            Paragraph(trail["name"], styles["trail_title"]),
            Paragraph(trail.get("state") or "Malaysia", styles["state"]),
        ]],
        colWidths=[12 * mm, 119 * mm, 43 * mm],
        style=TableStyle([
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("LEFTPADDING", (0, 0), (-1, -1), 0),
            ("RIGHTPADDING", (0, 0), (-1, -1), 4),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
        ]),
    )
    map_image = RLImage(str(map_path), width=174 * mm, height=52 * mm)
    attribution = Paragraph(
        "Mapbox base map (c) Mapbox (c) OpenStreetMap | Green line: saved Firebase route | Pins: HikerCircle cautions",
        styles["attribution"],
    )
    card = Table(
        [
            [title],
            [map_image],
            [attribution],
            [Paragraph(conclusion, styles["body"])],
            [summary_chips(counts, styles)],
        ],
        colWidths=[180 * mm],
        style=TableStyle([
            ("BACKGROUND", (0, 0), (-1, -1), colors.white),
            ("BOX", (0, 0), (-1, -1), 0.7, LINE),
            ("LEFTPADDING", (0, 0), (-1, -1), 3 * mm),
            ("RIGHTPADDING", (0, 0), (-1, -1), 3 * mm),
            ("TOPPADDING", (0, 0), (-1, -1), 3 * mm),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 3 * mm),
            ("TOPPADDING", (0, 1), (0, 2), 0),
            ("BOTTOMPADDING", (0, 1), (0, 2), 0),
            ("TOPPADDING", (0, 3), (0, 3), 2 * mm),
            ("BOTTOMPADDING", (0, 3), (0, 3), 1 * mm),
            ("TOPPADDING", (0, 4), (0, 4), 0),
        ]),
    )
    return KeepTogether([card])


def build_styles():
    styles = getSampleStyleSheet()
    styles.add(ParagraphStyle(name="cover_kicker", fontName="Helvetica-Bold", fontSize=10, leading=13, textColor=GREEN, spaceAfter=8))
    styles.add(ParagraphStyle(name="cover_title", fontName="Helvetica-Bold", fontSize=30, leading=34, textColor=colors.white, spaceAfter=12))
    styles.add(ParagraphStyle(name="cover_body", fontName="Helvetica", fontSize=11, leading=17, textColor=colors.HexColor("#CDE6D5")))
    styles.add(ParagraphStyle(name="h1x", fontName="Helvetica-Bold", fontSize=21, leading=25, textColor=INK, spaceAfter=8))
    styles.add(ParagraphStyle(name="h2x", fontName="Helvetica-Bold", fontSize=13, leading=16, textColor=INK, spaceBefore=5, spaceAfter=4))
    styles.add(ParagraphStyle(name="body", fontName="Helvetica", fontSize=8.5, leading=12, textColor=INK))
    styles.add(ParagraphStyle(name="small_muted", fontName="Helvetica", fontSize=8, leading=11, textColor=MUTED))
    styles.add(ParagraphStyle(name="chip", fontName="Helvetica", fontSize=7.2, leading=9, textColor=INK))
    styles.add(ParagraphStyle(name="trail_title", fontName="Helvetica-Bold", fontSize=12, leading=14, textColor=INK))
    styles.add(ParagraphStyle(name="state", fontName="Helvetica", fontSize=8.5, leading=11, alignment=2, textColor=MUTED))
    styles.add(ParagraphStyle(name="number", fontName="Helvetica-Bold", fontSize=11, leading=13, textColor=GREEN, alignment=TA_CENTER))
    styles.add(ParagraphStyle(name="attribution", fontName="Helvetica", fontSize=5.8, leading=7, textColor=MUTED, alignment=2))
    styles.add(ParagraphStyle(name="legend", fontName="Helvetica", fontSize=8.5, leading=11, textColor=INK))
    return styles


def main():
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    audit_data = json.loads(AUDIT_PATH.read_text(encoding="utf-8"))
    trails_input = json.loads(TRAIL_INPUT_PATH.read_text(encoding="utf-8"))
    audits = {item["trailId"]: item for item in audit_data["trails"]}
    trails = sorted(
        [item for item in trails_input if item.get("trailId") in audits],
        key=lambda item: item.get("name", "").lower(),
    )
    token = read_mapbox_token()
    map_paths = {}
    for index, trail in enumerate(trails, 1):
        print(f"Rendering Mapbox trail preview {index}/{len(trails)}: {trail['name']}")
        map_paths[trail["trailId"]] = make_map_preview(
            trail, audits[trail["trailId"]], token
        )

    styles = build_styles()
    total_counts = Counter()
    for audit in audits.values():
        total_counts.update(audit.get("counts", {}))
    overall_total = sum(audit.get("total", 0) for audit in audits.values())
    matched_trails = sum(1 for audit in audits.values() if audit.get("total", 0))
    zero_trails = len(trails) - matched_trails
    doc = BaseDocTemplate(
        str(OUTPUT_PATH),
        pagesize=A4,
        leftMargin=15 * mm,
        rightMargin=15 * mm,
        topMargin=17 * mm,
        bottomMargin=14 * mm,
        title="HikerCircle Trail Map Caution Reference",
        author="HikerCircle",
        subject="Live Firebase trail caution audit and Mapbox in-app reference",
    )
    frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id="main")
    doc.addPageTemplates(PageTemplate(id="all", frames=[frame], onPage=on_page))
    story = []

    cover = Table(
        [[[
            Spacer(1, 25 * mm),
            Paragraph("LIVE FIREBASE TRAIL AUDIT", styles["cover_kicker"]),
            Paragraph("Trail map<br/>caution reference", styles["cover_title"]),
            Paragraph(
                "All 35 saved HikerCircle trails, classified using the implemented water-crossing, steep-section, assisted-section and surface rules. Every preview uses the Mapbox Outdoors base map and the actual HikerCircle marker artwork.",
                styles["cover_body"],
            ),
            Spacer(1, 18 * mm),
            Paragraph("AUDIT SNAPSHOT", styles["cover_kicker"]),
            Paragraph(
                f"{overall_total} cautions | {matched_trails} trails with matches | {zero_trails} trails with no mapped match",
                styles["cover_body"],
            ),
            Spacer(1, 30 * mm),
        ]]],
        colWidths=[181 * mm],
        rowHeights=[240 * mm],
        style=TableStyle([
            ("BACKGROUND", (0, 0), (-1, -1), DARK_GREEN),
            ("LEFTPADDING", (0, 0), (-1, -1), 12 * mm),
            ("RIGHTPADDING", (0, 0), (-1, -1), 12 * mm),
            ("TOPPADDING", (0, 0), (-1, -1), 0),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
        ]),
    )
    story.extend([cover, PageBreak()])

    story.append(Paragraph("What changed", styles["h1x"]))
    story.append(Paragraph(
        "Mapbox remains the only map shown in HikerCircle. OpenStreetMap and Open-Meteo are data-only enrichment sources; their results are cached as HikerCircle caution records and drawn as Mapbox annotations.",
        styles["body"],
    ))
    story.append(Spacer(1, 4 * mm))
    story.append(Paragraph("Live catalogue result", styles["h2x"]))
    overview_rows = [["Caution", "Count", "Detection result"]]
    ordered_types = [
        "ford_crossing", "stepping_stones", "river", "stream",
        "steep_ascent", "steep_descent", "rope_assisted_section",
        "ladder_section", "scrambling_section", "loose_rock",
        "muddy_surface", "rough_surface", "bridge_crossing", "cliff",
    ]
    for hazard_type in ordered_types:
        count = total_counts.get(hazard_type, 0)
        note = "Matched in current Firebase routes" if count else "No matching source tag in current routes"
        overview_rows.append([
            LABELS[hazard_type], str(count), note,
        ])
    overview = Table(overview_rows, colWidths=[52 * mm, 20 * mm, 103 * mm], repeatRows=1)
    overview.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), DARK_GREEN),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTNAME", (0, 1), (-1, -1), "Helvetica"),
        ("FONTSIZE", (0, 0), (-1, -1), 8),
        ("TEXTCOLOR", (0, 1), (-1, -1), INK),
        ("BACKGROUND", (0, 1), (-1, -1), colors.white),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, PALE]),
        ("GRID", (0, 0), (-1, -1), 0.4, LINE),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
    ]))
    story.extend([overview, Spacer(1, 5 * mm)])
    story.append(Paragraph(
        "Zero is a valid conclusion: it means the route's current public tags did not meet the implemented threshold. It does not mean the physical hazard is absent.",
        styles["small_muted"],
    ))
    story.append(PageBreak())

    story.append(Paragraph("Marker legend", styles["h1x"]))
    story.append(Paragraph(
        "Each caution has its own icon and colour. These same PNG markers are generated by the Flutter marker renderer used on Mapbox.",
        styles["body"],
    ))
    story.append(Spacer(1, 5 * mm))
    legend_rows = []
    for index in range(0, len(ordered_types), 2):
        row = []
        for hazard_type in ordered_types[index : index + 2]:
            row.extend([
                icon_cell(hazard_type, 12 * mm),
                Paragraph(
                    f"<b>{LABELS[hazard_type]}</b><br/><font color='#637168'>{total_counts.get(hazard_type, 0)} live matches</font>",
                    styles["legend"],
                ),
            ])
        while len(row) < 4:
            row.extend(["", ""])
        legend_rows.append(row)
    legend = Table(legend_rows, colWidths=[16 * mm, 70 * mm, 16 * mm, 70 * mm])
    legend.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), colors.white),
        ("BOX", (0, 0), (-1, -1), 0.5, LINE),
        ("INNERGRID", (0, 0), (-1, -1), 0.3, LINE),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("TOPPADDING", (0, 0), (-1, -1), 7),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
    ]))
    story.append(legend)
    story.append(Spacer(1, 7 * mm))
    story.append(Paragraph("Water warning rule", styles["h2x"]))
    story.append(Paragraph(
        "A generic river or stream pin is retained only within 10 m of the saved route and only when no mapped bridge or ford is within 30 m. A ford receives its own ford icon; a bridge receives its own bridge icon. This removes the previous flood of nearby-water warnings.",
        styles["body"],
    ))
    story.append(Spacer(1, 3 * mm))
    story.append(Paragraph("Steep warning rule", styles["h2x"]))
    story.append(Paragraph(
        "Elevation samples are spaced at about 100 m and evaluated over a sustained roughly 300 m window. A pin requires at least 25% grade and at least 15 m rise or drop, with adjacent same-direction samples grouped into one section.",
        styles["body"],
    ))
    story.append(PageBreak())

    story.append(Paragraph("Every Firebase trail", styles["h1x"]))
    story.append(Paragraph(
        "The following pages conclude every document currently stored in the Firebase trails collection. Maps use each document's saved route polyline and caution coordinates from the completed live audit.",
        styles["body"],
    ))
    story.append(Spacer(1, 5 * mm))
    for index, trail in enumerate(trails, 1):
        story.append(trail_block(
            trail,
            audits[trail["trailId"]],
            map_paths[trail["trailId"]],
            index,
            styles,
        ))
        story.append(Spacer(1, 4 * mm))
        if index % 2 == 0 and index != len(trails):
            story.append(PageBreak())

    story.append(PageBreak())
    story.append(Paragraph("Interpretation and limitations", styles["h1x"]))
    bullets = [
        "The report reflects the 35 Firebase trail documents and provider responses at audit time.",
        "Public map tags may be absent, imprecise or out of date. A zero result is not a safety guarantee.",
        "Elevation uses a terrain model rather than a surveyed trail profile; dense switchbacks and short obstacles may not be resolved.",
        "Current rain, flooding, erosion, closures and damaged structures require live checks and local authority advice.",
        "Extended providers fail independently so a temporary enrichment outage does not remove the core Mapbox hazard dataset.",
        "The downloaded caution set is cached in SQLite and refreshed after 30 days; this release uses a new cache namespace so existing devices rescan.",
    ]
    for item in bullets:
        story.append(Paragraph(f"- {item}", styles["body"]))
        story.append(Spacer(1, 2 * mm))
    story.append(Spacer(1, 5 * mm))
    story.append(Paragraph("Data references", styles["h2x"]))
    refs = [
        "Mapbox Streets v8: https://docs.mapbox.com/data/tilesets/reference/mapbox-streets-v8/",
        "OpenStreetMap attribution: https://www.openstreetmap.org/copyright",
        "Overpass API: https://wiki.openstreetmap.org/wiki/Overpass_API",
        "Open-Meteo Elevation: https://open-meteo.com/en/docs/elevation-api",
    ]
    for item in refs:
        story.append(Paragraph(item, styles["small_muted"]))
        story.append(Spacer(1, 1.5 * mm))

    doc.build(story)
    print(f"Created {OUTPUT_PATH}")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(error, file=sys.stderr)
        raise
