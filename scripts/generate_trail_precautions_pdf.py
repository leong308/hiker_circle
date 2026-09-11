from pathlib import Path
import re
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak

root = Path(__file__).resolve().parents[1]
import sys
document_name = sys.argv[1] if len(sys.argv) > 1 else 'trail-precaution-rules'
src = (root / 'docs' / f'{document_name}.md').read_text(encoding='utf-8')
src = (src.replace('\u2014', '-').replace('\u2013', '-').replace('\u2265', '>=')
          .replace('\u2264', '<=').replace('\u2192', '->').replace('\u00d7', 'x'))
out = root / 'output' / 'pdf' / f'{document_name}.pdf'
out.parent.mkdir(parents=True, exist_ok=True)
green, ink, muted, pale = (colors.HexColor(x) for x in ('#39B86A','#193129','#60736B','#EAF7EF'))
s = getSampleStyleSheet()
s.add(ParagraphStyle(name='H1x', parent=s['Heading1'], fontName='Helvetica-Bold', fontSize=18, leading=22, textColor=ink, spaceBefore=12, spaceAfter=8))
s.add(ParagraphStyle(name='H2x', parent=s['Heading2'], fontName='Helvetica-Bold', fontSize=11, leading=14, textColor=green, spaceBefore=8, spaceAfter=4))
s.add(ParagraphStyle(name='Bx', parent=s['BodyText'], fontName='Helvetica', fontSize=8.2, leading=11.5, textColor=ink, spaceAfter=4))
s.add(ParagraphStyle(name='Cx', parent=s['BodyText'], fontName='Helvetica', fontSize=6.3, leading=7.7, textColor=ink))
s.add(ParagraphStyle(name='Ch', parent=s['BodyText'], fontName='Helvetica-Bold', fontSize=6.3, leading=7.7, textColor=colors.white))
s.add(ParagraphStyle(name='CoverTitle', parent=s['Title'], fontName='Helvetica-Bold', fontSize=27, leading=31, textColor=colors.white))
s.add(ParagraphStyle(name='CoverSub', parent=s['BodyText'], fontName='Helvetica', fontSize=10, leading=14, textColor=colors.HexColor('#DDF4E5')))

def clean(x):
    x = x.replace('**','')
    x = re.sub(r'`([^`]+)`', r'\1', x)
    x = re.sub(r'\[([^]]+)\]\(([^)]+)\)', r'\1', x)
    return x.replace('&','&amp;').replace('<','&lt;').replace('>','&gt;')

story = [Spacer(1, 10)]
title = 'SOS mechanism' if document_name == 'SOS_MECHANISM' else 'Trail precaution rules'
subtitle = 'Emergency triggers, delivery paths and platform safety behavior' if document_name == 'SOS_MECHANISM' else 'Dynamic advisories for Malaysian trail planning'
purpose = ('This document describes HikerCircle SOS detection, escalation, location relay, cancellation, delivery and platform safety behavior. '
           'It is an implementation reference for emergency flows and their failure handling.' if document_name == 'SOS_MECHANISM' else
           'This document defines when HikerCircle displays trail precautions, sends upcoming-hike FCM reminders and reads newly detected cautions during active hikes. Missing inputs are explicitly disclosed and never treated as safe conditions.')
footer_label = 'HikerCircle | SOS mechanism' if document_name == 'SOS_MECHANISM' else 'HikerCircle | Trail precaution rules'
story.append(Table([[Paragraph('HIKER CIRCLE', s['CoverSub'])],[Paragraph(title, s['CoverTitle'])],[Paragraph(subtitle, s['CoverSub'])],[Spacer(1,10)],[Paragraph('Implementation reference | Reconciled 10 September 2026', s['CoverSub'])]], colWidths=[166*mm], style=TableStyle([('BACKGROUND',(0,0),(-1,-1),colors.HexColor('#173C2A')),('LEFTPADDING',(0,0),(-1,-1),16),('RIGHTPADDING',(0,0),(-1,-1),16),('TOPPADDING',(0,0),(-1,-1),10),('BOTTOMPADDING',(0,0),(-1,-1),10)])))
story += [Spacer(1,14), Paragraph('Purpose',s['H1x']), Paragraph(purpose,s['Bx']), PageBreak()]
lines = src.splitlines(); i = 0
while i < len(lines):
    line = lines[i]
    if not line.strip() or line.startswith('# ') or line.strip().startswith('```'): i += 1; continue
    if line.startswith('## '): story.append(Paragraph(clean(line[3:]),s['H1x'])); i += 1; continue
    if line.startswith('### '): story.append(Paragraph(clean(line[4:]),s['H2x'])); i += 1; continue
    if line.startswith('|') and i+1 < len(lines) and lines[i+1].startswith('|---'):
        rows=[]
        while i < len(lines) and lines[i].startswith('|'):
            if not set(lines[i].replace('|','').replace('-','').replace(':','').replace(' ','')): i += 1; continue
            rows.append([x.strip() for x in lines[i].strip('|').split('|')]); i += 1
        data = [[Paragraph(clean(x),s['Ch']) for x in rows[0]]] + [[Paragraph(clean(x),s['Cx']) for x in r] for r in rows[1:]]
        n=len(rows[0]); widths={2:[55,111],3:[35,65,66],4:[24,45,68,29]}.get(n,[166/n]*n)
        t=Table(data,colWidths=[w*mm for w in widths],repeatRows=1,hAlign='LEFT'); t.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,0),green),('ROWBACKGROUNDS',(0,1),(-1,-1),[colors.white,pale]),('GRID',(0,0),(-1,-1),.25,colors.HexColor('#C8DCD0')),('VALIGN',(0,0),(-1,-1),'TOP'),('LEFTPADDING',(0,0),(-1,-1),4),('RIGHTPADDING',(0,0),(-1,-1),4),('TOPPADDING',(0,0),(-1,-1),4),('BOTTOMPADDING',(0,0),(-1,-1),4)])); story += [Spacer(1,4),t,Spacer(1,7)]; continue
    prefix='- ' if line.startswith('- ') else ''
    story.append(Paragraph(prefix+clean(line[2:] if prefix else line),s['Bx'])); i += 1

def footer(c, d):
    c.saveState(); c.setStrokeColor(colors.HexColor('#D6E8DC')); c.line(18*mm,13*mm,192*mm,13*mm); c.setFont('Helvetica',7); c.setFillColor(muted); c.drawString(18*mm,8*mm,footer_label); c.drawRightString(192*mm,8*mm,f'Page {d.page}'); c.restoreState()
pdf_title = 'HikerCircle SOS mechanism' if document_name == 'SOS_MECHANISM' else 'HikerCircle Trail Precaution Rules'
doc=SimpleDocTemplate(str(out),pagesize=A4,leftMargin=22*mm,rightMargin=22*mm,topMargin=18*mm,bottomMargin=18*mm,title=pdf_title,author='HikerCircle')
doc.build(story,onFirstPage=footer,onLaterPages=footer)
print(out)
