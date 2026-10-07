#!/usr/bin/env python3
"""Render the repository's research chapters to a standalone, linked PDF."""
from html import escape
from pathlib import Path
import re
import textwrap
from urllib.parse import urlsplit

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    Flowable, KeepTogether, PageBreak, Paragraph, SimpleDocTemplate,
    Spacer, Table, TableStyle,
)
from svglib.svglib import svg2rlg

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/research"
WIDTH, HEIGHT = A4
CONTENT_WIDTH = WIDTH - 112
NAVY = colors.HexColor("#15263d")
BLUE = colors.HexColor("#147caf")


def fonts():
    directory = Path("/usr/share/fonts/truetype/dejavu")
    for name, file in (("DejaVu Sans", "DejaVuSans.ttf"),
                       ("SWSerif", "DejaVuSerif.ttf"),
                       ("SWSerifBold", "DejaVuSerif-Bold.ttf"),
                       ("SWSans", "DejaVuSans.ttf"),
                       ("SWSansBold", "DejaVuSans-Bold.ttf"),
                       ("SWMono", "DejaVuSansMono.ttf")):
        pdfmetrics.registerFont(TTFont(name, str(directory / file)))
    pdfmetrics.registerFontFamily("SWSerif", normal="SWSerif", bold="SWSerifBold",
                                  italic="SWSerif", boldItalic="SWSerifBold")
    pdfmetrics.registerFontFamily("SWSans", normal="SWSans", bold="SWSansBold",
                                  italic="SWSans", boldItalic="SWSansBold")


def inline(text, source):
    fragments = []
    pattern = r"\[([^\]]+)\]\(([^)]+)\)|`([^`]+)`|\*\*([^*]+)\*\*|\*([^*]+)\*"
    position = 0
    for match in re.finditer(pattern, text):
        fragments.append(escape(text[position:match.start()]))
        label, target, code, bold, italic = match.groups()
        if target:
            if not urlsplit(target).scheme:
                path = (source.parent / target).resolve().relative_to(ROOT)
                target = "https://github.com/parrsi01/securewave/blob/master/" + str(path)
            fragments.append(f'<link href="{escape(target, quote=True)}" color="#147caf">{escape(label)}</link>')
        elif code:
            fragments.append(f'<font name="SWMono" size="8.5">{escape(code)}</font>')
        elif bold:
            fragments.append(f"<b>{escape(bold)}</b>")
        else:
            fragments.append(f"<i>{escape(italic)}</i>")
        position = match.end()
    fragments.append(escape(text[position:]))
    return "".join(fragments)


class CodeBlock(Flowable):
    def __init__(self, lines):
        super().__init__()
        self.lines = []
        for line in lines:
            self.lines.extend(textwrap.wrap(line, width=94, replace_whitespace=False,
                                           drop_whitespace=False, subsequent_indent="    ") or [""])
        self.width = CONTENT_WIDTH
        self.height = len(self.lines) * 11 + 20

    def draw(self):
        canvas = self.canv
        canvas.setFillColor(colors.HexColor("#f1f5f8"))
        canvas.rect(0, 0, self.width, self.height, stroke=0, fill=1)
        canvas.setFillColor(NAVY)
        canvas.setFont("SWMono", 7.5)
        for i, line in enumerate(self.lines):
            canvas.drawString(10, self.height - 15 - 11 * i, line)


def styles():
    base = getSampleStyleSheet()
    return {
        "body": ParagraphStyle("Body", fontName="SWSerif", fontSize=10,
                               leading=15, spaceAfter=8, textColor=NAVY),
        "h1": ParagraphStyle("Chapter", fontName="SWSansBold", fontSize=19,
                             leading=25, spaceAfter=20, textColor=NAVY),
        "h2": ParagraphStyle("Section", fontName="SWSansBold", fontSize=12,
                             leading=18, spaceBefore=13, spaceAfter=7,
                             textColor=BLUE, keepWithNext=True),
        "cell": ParagraphStyle("Cell", fontName="SWSans", fontSize=8,
                               leading=11, textColor=NAVY, wordWrap="CJK"),
        "caption": ParagraphStyle("Caption", fontName="SWSans", fontSize=8.5,
                                  leading=12, spaceAfter=12, textColor=BLUE),
        "title": ParagraphStyle("Title", parent=base["Title"], fontName="SWSansBold",
                                fontSize=27, leading=35, textColor=NAVY),
        "subtitle": ParagraphStyle("Subtitle", fontName="SWSans", fontSize=12,
                                   leading=19, alignment=TA_CENTER, textColor=BLUE),
    }


def chapter(path, index, st):
    result, lines, i = [], path.read_text().splitlines(), 0
    while i < len(lines):
        line = lines[i]
        if not line.strip():
            i += 1
            continue
        if line.startswith("# "):
            result.append(Paragraph(f'<a name="chapter-{index}"/>' + inline(line[2:], path), st["h1"]))
        elif line.startswith("## "):
            result.append(Paragraph(inline(line[3:], path), st["h2"]))
        elif line.startswith("```"):
            block, i = [], i + 1
            while i < len(lines) and not lines[i].startswith("```"):
                block.append(lines[i]); i += 1
            result.extend([KeepTogether([CodeBlock(block)]), Spacer(1, 12)])
        elif line.startswith("!["):
            match = re.fullmatch(r"!\[([^\]]+)\]\(([^)]+)\)", line)
            drawing = svg2rlg(str(path.parent / match[2]))
            scale = CONTENT_WIDTH / drawing.width
            drawing.scale(scale, scale)
            drawing.width *= scale; drawing.height *= scale
            result.append(KeepTogether([drawing, Paragraph(escape(match[1]), st["caption"])]))
        elif line.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                cells = [cell.strip() for cell in lines[i].strip("|").split("|")]
                if not all(re.fullmatch(r":?-+:?", cell) for cell in cells):
                    rows.append([Paragraph(inline(cell, path), st["cell"]) for cell in cells])
                i += 1
            table = Table(rows, colWidths=[CONTENT_WIDTH / len(rows[0])] * len(rows[0]), repeatRows=1)
            table.setStyle(TableStyle([
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e6f1f7")),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LINEBELOW", (0, 0), (-1, 0), .7, BLUE),
                ("LINEBELOW", (0, 1), (-1, -1), .3, colors.HexColor("#d9e1e8")),
                ("LEFTPADDING", (0, 0), (-1, -1), 7),
                ("RIGHTPADDING", (0, 0), (-1, -1), 7),
                ("TOPPADDING", (0, 0), (-1, -1), 7),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
            ]))
            result.extend([table, Spacer(1, 12)])
            continue
        else:
            block = [line]; i += 1
            while i < len(lines) and lines[i].strip() and not re.match(r"^(#|\||```|!\[|- )", lines[i]):
                block.append(lines[i]); i += 1
            text = " ".join(part.strip() for part in block)
            if text.startswith("- "):
                result.append(Paragraph(inline(text[2:], path), st["body"], bulletText="•"))
            else:
                result.append(Paragraph(inline(text, path), st["body"]))
            continue
        i += 1
    return result


def page(canvas, doc):
    canvas.saveState()
    canvas.setFont("SWSans", 8)
    canvas.setFillColor(BLUE)
    if doc.page > 1:
        canvas.drawString(56, HEIGHT - 35, "SECUREWAVE 1.0.0  /  ARCHITECTURE AND ASSURANCE")
    canvas.setStrokeColor(colors.HexColor("#d9e1e8"))
    canvas.line(56, 44, WIDTH - 56, 44)
    canvas.setFillColor(NAVY)
    canvas.drawString(56, 29, "Repository engineering report • 7 October 2026")
    canvas.drawRightString(WIDTH - 56, 29, str(doc.page))
    canvas.restoreState()


def main():
    fonts(); st = styles()
    paths = [*sorted(SOURCE.glob("[0-9][0-9]-*.md")), SOURCE / "references.md"]
    story = [Spacer(1, 120), Paragraph("SecureWave", st["title"]), Spacer(1, 18),
             Paragraph("Architecture, Algorithms<br/>and Assurance", st["title"]),
             Spacer(1, 40), Paragraph("Master's-level engineering analysis<br/>Source version 1.0.0", st["subtitle"]),
             Spacer(1, 36), Paragraph("Project author: Simon Parris<br/>7 October 2026", st["subtitle"]),
             Spacer(1, 48), Paragraph("A source-backed case study of a Linux WireGuard application: "
                                      "privilege separation, verified lifecycle, durable accounting and reproducible delivery.", st["body"]),
             Paragraph("Engineering documentation; not a peer-reviewed publication or security certification.", st["caption"]), PageBreak(),
             Paragraph("Contents", st["h1"])]
    for index, path in enumerate(paths):
        title = path.read_text().splitlines()[0][2:]
        story.append(Paragraph(f'<link href="#chapter-{index}" color="#147caf">{escape(title)}</link>', st["body"]))
    story.extend([Spacer(1, 20), Paragraph("The accompanying Markdown chapters and SVG figures are the source of this report. "
                                          "The reference manuscript supplies a structural example; its machine learning results "
                                          "are not SecureWave features.", st["body"])])
    for index, path in enumerate(paths):
        story.append(PageBreak()); story.extend(chapter(path, index, st))
    output = SOURCE / "securewave-architecture.pdf"
    doc = SimpleDocTemplate(str(output), pagesize=A4, rightMargin=56, leftMargin=56,
                            topMargin=58, bottomMargin=61, invariant=1,
                            title="SecureWave: Architecture, Algorithms and Assurance",
                            author="SecureWave project; Simon Parris", subject="Repository engineering report for version 1.0.0")
    doc.build(story, onFirstPage=page, onLaterPages=page)
    print(f"Built {output.relative_to(ROOT)} ({output.stat().st_size:,} bytes).")


if __name__ == "__main__":
    main()
