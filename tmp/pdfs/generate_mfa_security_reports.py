from __future__ import annotations

import os
from datetime import datetime, timezone

from reportlab.graphics.shapes import Drawing, Line, Rect, String
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    KeepTogether,
    LongTable,
    PageBreak,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfbase import pdfmetrics


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = os.path.join(ROOT, 'output', 'pdf')
os.makedirs(OUT, exist_ok=True)

REPORT_DATE = '29 August 2026'
ASSESSMENT_ID = 'HC-MFA-2026-08-29'
BASELINE_REF = 'f7fb8d8 (working tree contained pre-existing changes)'

NAVY = colors.HexColor('#15352A')
GREEN = colors.HexColor('#3F8F5E')
LIGHT_GREEN = colors.HexColor('#EAF7EE')
MINT = colors.HexColor('#CFE5D6')
INK = colors.HexColor('#14221B')
MUTED = colors.HexColor('#59675F')
RED = colors.HexColor('#C9363E')
AMBER = colors.HexColor('#D68516')
YELLOW = colors.HexColor('#F5C451')
BLUE = colors.HexColor('#2F80ED')
PAPER = colors.HexColor('#F7FAF8')


def register_fonts():
    candidates = [
        os.path.join(ROOT, 'assets', 'fonts', 'InterVariable.ttf'),
        r'C:\Windows\Fonts\arial.ttf',
    ]
    for path in candidates:
        if os.path.exists(path):
            try:
                pdfmetrics.registerFont(TTFont('HCBody', path))
                return 'HCBody'
            except Exception:
                pass
    return 'Helvetica'


FONT = register_fonts()


def styles():
    base = getSampleStyleSheet()
    return {
        'title': ParagraphStyle(
            'Title', parent=base['Title'], fontName=FONT, fontSize=27,
            leading=32, textColor=colors.white, alignment=TA_LEFT,
            spaceAfter=8,
        ),
        'subtitle': ParagraphStyle(
            'Subtitle', parent=base['Normal'], fontName=FONT, fontSize=12,
            leading=17, textColor=colors.HexColor('#D8EDE1'),
        ),
        'h1': ParagraphStyle(
            'H1', parent=base['Heading1'], fontName=FONT, fontSize=19,
            leading=24, textColor=NAVY, spaceBefore=8, spaceAfter=10,
        ),
        'h2': ParagraphStyle(
            'H2', parent=base['Heading2'], fontName=FONT, fontSize=14,
            leading=18, textColor=GREEN, spaceBefore=10, spaceAfter=7,
        ),
        'h3': ParagraphStyle(
            'H3', parent=base['Heading3'], fontName=FONT, fontSize=11.5,
            leading=15, textColor=NAVY, spaceBefore=8, spaceAfter=5,
        ),
        'body': ParagraphStyle(
            'Body', parent=base['BodyText'], fontName=FONT, fontSize=9.3,
            leading=13.4, textColor=INK, spaceAfter=7,
        ),
        'small': ParagraphStyle(
            'Small', parent=base['BodyText'], fontName=FONT, fontSize=7.7,
            leading=10.7, textColor=MUTED, spaceAfter=4,
        ),
        'callout': ParagraphStyle(
            'Callout', parent=base['BodyText'], fontName=FONT, fontSize=9.4,
            leading=13.6, textColor=NAVY, leftIndent=9, rightIndent=9,
            borderColor=MINT, borderWidth=1, borderPadding=9,
            backColor=LIGHT_GREEN, spaceBefore=5, spaceAfter=9,
        ),
        'code': ParagraphStyle(
            'Code', parent=base['Code'], fontName='Courier', fontSize=7.4,
            leading=10, textColor=INK, backColor=colors.HexColor('#EFF3F0'),
            borderPadding=6, spaceAfter=6,
        ),
        'toc': ParagraphStyle(
            'TOC', parent=base['BodyText'], fontName=FONT, fontSize=9.5,
            leading=14, textColor=INK, leftIndent=6,
        ),
    }


S = styles()


def P(text, style='body'):
    return Paragraph(text, S[style])


def bullet(text):
    return Paragraph(f'&#8226;&nbsp;&nbsp;{text}', S['body'])


def severity_color(value):
    return {
        'Critical': colors.HexColor('#7A0012'),
        'High': RED,
        'Medium': AMBER,
        'Low': BLUE,
        'Info': GREEN,
    }.get(value, MUTED)


class SecurityDoc(BaseDocTemplate):
    def __init__(self, filename, title, report_kind):
        super().__init__(
            filename,
            pagesize=A4,
            rightMargin=17 * mm,
            leftMargin=17 * mm,
            topMargin=20 * mm,
            bottomMargin=18 * mm,
            title=title,
            author='HikerCircle Security Engineering',
            subject=report_kind,
        )
        frame = Frame(self.leftMargin, self.bottomMargin, self.width, self.height, id='main')
        self.addPageTemplates(PageTemplate(id='security', frames=[frame], onPage=self._page))
        self.report_title = title
        self.report_kind = report_kind

    def _page(self, canvas, doc):
        canvas.saveState()
        canvas.setFillColor(NAVY)
        canvas.rect(0, A4[1] - 13 * mm, A4[0], 13 * mm, fill=1, stroke=0)
        canvas.setFont(FONT, 7.5)
        canvas.setFillColor(colors.white)
        canvas.drawString(17 * mm, A4[1] - 8.4 * mm, 'HikerCircle  |  Security Assurance')
        canvas.drawRightString(A4[0] - 17 * mm, A4[1] - 8.4 * mm, self.report_kind)
        canvas.setStrokeColor(MINT)
        canvas.line(17 * mm, 13 * mm, A4[0] - 17 * mm, 13 * mm)
        canvas.setFillColor(MUTED)
        canvas.setFont(FONT, 7.2)
        canvas.drawString(17 * mm, 8.5 * mm, f'{ASSESSMENT_ID}  |  Confidential project documentation')
        canvas.drawRightString(A4[0] - 17 * mm, 8.5 * mm, f'Page {doc.page}')
        canvas.restoreState()


def cover(title, subtitle, classification='Project Confidential'):
    d = Drawing(176 * mm, 120 * mm)
    d.add(Rect(0, 0, 176 * mm, 120 * mm, rx=8, ry=8, fillColor=NAVY, strokeColor=NAVY))
    d.add(Rect(0, 0, 9 * mm, 120 * mm, fillColor=GREEN, strokeColor=GREEN))
    d.add(String(18 * mm, 95 * mm, 'HIKERCIRCLE', fontName=FONT, fontSize=11, fillColor=colors.HexColor('#AEE4C2')))
    lines = title.split('\n')
    y = 76 * mm
    for line in lines:
        d.add(String(18 * mm, y, line, fontName=FONT, fontSize=24, fillColor=colors.white))
        y -= 12 * mm
    d.add(String(18 * mm, 31 * mm, subtitle, fontName=FONT, fontSize=10, fillColor=colors.HexColor('#D8EDE1')))
    d.add(String(18 * mm, 20 * mm, f'{REPORT_DATE}  |  {ASSESSMENT_ID}', fontName=FONT, fontSize=8.5, fillColor=colors.white))
    d.add(String(18 * mm, 11 * mm, classification, fontName=FONT, fontSize=8, fillColor=colors.HexColor('#AEE4C2')))
    return [Spacer(1, 21 * mm), d, Spacer(1, 13 * mm), P(
        'Prepared for project documentation. This is a point-in-time technical assessment, not a certification, guarantee of security, or substitute for a production release review on physical devices.',
        'small'
    ), PageBreak()]


def document_control(report_name, scope):
    data = [
        ['Field', 'Value'],
        ['Report', report_name],
        ['Assessment date', REPORT_DATE],
        ['Assessment ID', ASSESSMENT_ID],
        ['Application', 'HikerCircle mobile application (Android and iOS)'],
        ['Baseline reference', BASELINE_REF],
        ['Primary scope', scope],
        ['Environment', 'Flutter mobile client, Firebase callable functions, Firestore, Firebase Hosting association metadata'],
        ['Classification', 'Project Confidential'],
    ]
    return [P('Document control', 'h1'), styled_table(data, [37 * mm, 136 * mm]), Spacer(1, 6 * mm)]


def styled_table(data, widths=None, header=True, font_size=7.7, repeat_rows=1):
    cooked = []
    for row in data:
        cooked.append([cell if hasattr(cell, 'wrap') else P(str(cell), 'small') for cell in row])
    table = LongTable(cooked, colWidths=widths, repeatRows=repeat_rows if header else 0, hAlign='LEFT')
    commands = [
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('GRID', (0, 0), (-1, -1), 0.4, colors.HexColor('#CBD7CF')),
        ('LEFTPADDING', (0, 0), (-1, -1), 6),
        ('RIGHTPADDING', (0, 0), (-1, -1), 6),
        ('TOPPADDING', (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
        ('BACKGROUND', (0, 1 if header else 0), (-1, -1), colors.white),
        ('ROWBACKGROUNDS', (0, 1 if header else 0), (-1, -1), [colors.white, PAPER]),
    ]
    if header:
        commands += [
            ('BACKGROUND', (0, 0), (-1, 0), NAVY),
            ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
        ]
    table.setStyle(TableStyle(commands))
    return table


def risk_summary(counts):
    order = ['Critical', 'High', 'Medium', 'Low', 'Info']
    cells = []
    for severity in order:
        cells.append(Table([
            [P(str(counts.get(severity, 0)), 'h1')],
            [P(severity, 'small')],
        ], colWidths=[31 * mm], style=TableStyle([
            ('BACKGROUND', (0, 0), (-1, -1), colors.HexColor('#FFFFFF')),
            ('BOX', (0, 0), (-1, -1), 1.2, severity_color(severity)),
            ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
            ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
            ('TOPPADDING', (0, 0), (-1, 0), 7),
            ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
        ])))
    return Table([cells], colWidths=[34 * mm] * 5, style=TableStyle([('VALIGN', (0, 0), (-1, -1), 'TOP')]))


def auth_flow(before=True):
    d = Drawing(174 * mm, 44 * mm)
    labels = (
        ['Phone / password', 'Legacy endpoint', 'Firebase token', 'Protected data']
        if before else
        ['WhatsApp OTP', 'MFA session', 'TOTP or passkey', 'Firebase token']
    )
    fills = [PAPER, LIGHT_GREEN, colors.HexColor('#FFF3DE'), PAPER]
    if not before:
        fills = [LIGHT_GREEN, colors.HexColor('#E9F1FF'), colors.HexColor('#FFF3DE'), LIGHT_GREEN]
    x_values = [0, 45 * mm, 90 * mm, 135 * mm]
    for i, (x, label) in enumerate(zip(x_values, labels)):
        d.add(Rect(x, 13 * mm, 37 * mm, 18 * mm, rx=4, ry=4, fillColor=fills[i], strokeColor=GREEN if not before else MUTED))
        d.add(String(x + 18.5 * mm, 23 * mm, label, textAnchor='middle', fontName=FONT, fontSize=6.6, fillColor=INK))
        if i < 3:
            d.add(Line(x + 37 * mm, 22 * mm, x + 44 * mm, 22 * mm, strokeColor=MUTED, strokeWidth=1.2))
    caption = 'Before: alternate token issuers could skip the second factor.' if before else 'After: no Firebase token is minted until the second factor succeeds.'
    d.add(String(87 * mm, 4 * mm, caption, textAnchor='middle', fontName=FONT, fontSize=7.3, fillColor=MUTED))
    return d


def finding_block(f):
    color = severity_color(f['severity'])
    header = Table([
        [P(f"{f['id']}  {f['title']}", 'h2'), P(f['severity'], 'h3')]
    ], colWidths=[142 * mm, 30 * mm], style=TableStyle([
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('BACKGROUND', (0, 0), (-1, -1), colors.HexColor('#F7FAF8')),
        ('BOX', (0, 0), (-1, -1), 1, color),
        ('ALIGN', (1, 0), (1, 0), 'CENTER'),
        ('LEFTPADDING', (0, 0), (-1, -1), 8),
        ('RIGHTPADDING', (0, 0), (-1, -1), 8),
    ]))
    rows = [
        ['Affected surface', f['surface']],
        ['Evidence', f['evidence']],
        ['Attack / failure scenario', f['scenario']],
        ['Impact', f['impact']],
        ['Recommendation', f['recommendation']],
        ['Status at baseline', f.get('status', 'Open')],
    ]
    return [header, Spacer(1, 3 * mm), styled_table(rows, [38 * mm, 134 * mm], header=False, repeat_rows=0), Spacer(1, 6 * mm)]


def toc(items):
    story = [P('Contents', 'h1')]
    for number, title in items:
        story.append(P(f'<b>{number}</b>&nbsp;&nbsp;&nbsp;{title}', 'toc'))
    story.append(PageBreak())
    return story


PRE_FINDINGS = [
    dict(id='VA-01', severity='High', title='Password-only login bypassed the intended second factor',
         surface='Callable function loginWithPassword and mobile Login mode.',
         evidence='The endpoint verified the Argon2 password and immediately called createCustomToken with verificationProvider=password.',
         scenario='An attacker with a reused, phished, or breached password could obtain a Firebase session without WhatsApp or another possession factor.',
         impact='Account takeover and access to profile, hike, location, Circle, and SOS-related data authorized by the Firebase token.',
         recommendation='Retire password-only token issuance. Require a verified WhatsApp challenge followed by TOTP or WebAuthn before minting the Firebase token.'),
    dict(id='VA-02', severity='High', title='Saved-device recovery could mint a token without MFA',
         surface='Callable function authenticateAppSession.',
         evidence='The unauthenticated recovery endpoint accepted phoneNumber and boundAppInstanceId, then returned a custom token without an MFA claim.',
         scenario='A copied local database or recovered app instance identifier could be replayed against the recovery endpoint.',
         impact='Bypass of newly introduced MFA and persistence of older device-session trust beyond its intended purpose.',
         recommendation='Disable this token issuer for MFA-protected accounts; require a fresh WhatsApp plus factor login when Firebase authentication is unavailable.'),
    dict(id='VA-03', severity='High', title='WhatsApp verification completed sign-in directly',
         surface='verifyGreenApiLoginCode.',
         evidence='A correct six-digit WhatsApp code was consumed and a Firebase custom token was returned immediately.',
         scenario='Compromise of WhatsApp, number reassignment, session theft, or social engineering was sufficient for account access.',
         impact='The design provided only one out-of-band possession proof and could not enforce the requested bound factor.',
         recommendation='Return a high-entropy, short-lived pre-authentication session instead of a Firebase token. Consume it only after TOTP or passkey verification.'),
    dict(id='VA-04', severity='High', title='No mandatory secondary-factor enrollment state',
         surface='Registration and account settings.',
         evidence='No factor registry, minimum-factor invariant, or enrollment gate existed in the baseline.',
         scenario='New and legacy accounts could remain indefinitely without Authenticator or passkey protection.',
         impact='Inconsistent account assurance and simple downgrade to the least protected login route.',
         recommendation='Create backend-owned factor records, require one factor before first Firebase token, and reject deletion of the final factor.'),
    dict(id='VA-05', severity='Medium', title='Passkey trust association was absent',
         surface='Android Digital Asset Links, iOS Associated Domains/AASA, server origin allowlist.',
         evidence='No passkey SDK, RP metadata, webcredentials entitlement, assetlinks.json, or WebAuthn server verifier was present.',
         scenario='A partial client-only passkey implementation would fail on physical devices or accept assertions without correct RP/origin binding.',
         impact='Unavailable or incorrectly scoped passkeys; potential verifier confusion if origins were accepted loosely.',
         recommendation='Use a single RP ID, exact Android signing origins, Apple app ID association, and server-side WebAuthn challenge/origin/signature verification.'),
    dict(id='VA-06', severity='Medium', title='No TOTP secret lifecycle controls',
         surface='Authenticator enrollment, storage, verification, and revocation.',
         evidence='The baseline had no RFC 6238 implementation or encrypted factor storage.',
         scenario='An ad hoc implementation could store plaintext seeds, accept replayed codes, or allow an excessive clock window.',
         impact='Second-factor cloning or replay, defeating the security benefit of Authenticator.',
         recommendation='Generate 160-bit seeds, encrypt using a Secret Manager key and AES-256-GCM, use a 30-second step with +/-1 window, and persist last-used step.'),
    dict(id='VA-07', severity='Medium', title='Android application backup was enabled',
         surface='AndroidManifest.xml and mobile local session database.',
         evidence='android:allowBackup was true while the local SQLite database contained app/session identity and user data.',
         scenario='Backup or device-transfer channels could copy durable local state to another environment.',
         impact='Increased exposure of local identifiers and cached sensitive data; amplified impact of the saved-session bypass.',
         recommendation='Disable Android backup for the application or exhaustively exclude authentication/session material.'),
    dict(id='VA-08', severity='Medium', title='Sensitive factor operations lacked a defined recent-MFA rule',
         surface='Future add/remove-factor settings operations.',
         evidence='No factor-management endpoints or step-up policy existed at baseline.',
         scenario='A stolen long-lived Firebase token could be used to add an attacker factor or remove a legitimate factor.',
         impact='Persistent account takeover and lockout.',
         recommendation='Require an MFA-authenticated Firebase token with auth_time no older than ten minutes, and retain at least one factor.'),
    dict(id='VA-09', severity='Low', title='Production passkey signing origin was not yet available',
         surface='Android release signing and Digital Asset Links.',
         evidence='The repository is configured for a development-only release key; the current SHA-256 certificate is the debug/development certificate.',
         scenario='A Play App Signing build uses another certificate and the server/assetlinks allowlist does not contain its origin.',
         impact='Passkey creation/authentication fails for store-distributed builds rather than creating an authentication bypass.',
         recommendation='Before store release, add the Play App Signing SHA-256 fingerprint to assetlinks.json and its base64url apk-key-hash origin to the server allowlist.'),
    dict(id='VA-10', severity='Low', title='MFA artifacts required retention and attempt bounds',
         surface='Pre-authentication sessions and WebAuthn challenges.',
         evidence='These stores did not exist at baseline, so expiration deletion and WebAuthn failure throttling had not been designed.',
         scenario='Expired encrypted enrollment seeds could accumulate; invalid signature submissions could consume verification CPU.',
         impact='Data-minimization and denial-of-service exposure.',
         recommendation='Bound attempts, mark challenges one-time, and delete expired sessions/challenges on a scheduled job.'),
    dict(id='VA-11', severity='Info', title='Backend JavaScript dependency audit reported no known vulnerabilities',
         surface='functions/package-lock.json production dependency graph.',
         evidence='npm audit reported 0 critical, high, moderate, low, or informational vulnerabilities at assessment time.',
         scenario='This result can change as advisories are published.',
         impact='No known dependency finding at this point in time.',
         recommendation='Keep lockfiles, automated audit checks, and periodic dependency review in CI.'),
]


def build_vulnerability_report(path):
    title = 'Pre-Remediation Vulnerability Assessment'
    story = []
    story += cover('Pre-Remediation\nVulnerability Assessment', 'Mobile login security: WhatsApp, TOTP, and passkeys')
    story += document_control(title, 'White-box review of the mobile authentication architecture before MFA remediation.')
    story += toc([
        ('1', 'Executive summary'), ('2', 'Scope and methodology'), ('3', 'Architecture and trust boundaries'),
        ('4', 'Risk model'), ('5', 'Detailed findings'), ('6', 'Remediation priorities'),
        ('7', 'Limitations'), ('A', 'Evidence and standards references'),
    ])
    story += [P('1. Executive summary', 'h1'), P(
        'The baseline mobile login architecture contained three independent ways to obtain a Firebase token without a bound secondary factor: password login, saved-device recovery, and successful WhatsApp OTP verification. Adding a visible Authenticator or passkey screen alone would therefore not have enforced MFA. Four findings were rated High because each affected the token-issuance trust boundary.',
    ), risk_summary({'High': 4, 'Medium': 4, 'Low': 2, 'Info': 1}), Spacer(1, 5 * mm),
    P('<b>Overall baseline risk: High.</b> The primary corrective objective is to make the backend, not the mobile UI, the enforcement point: no Firebase custom token may be created until WhatsApp and one enrolled secondary factor have both succeeded.', 'callout'),
    auth_flow(before=True), PageBreak()]
    story += [P('2. Scope and methodology', 'h1'), P(
        'The assessment used source-assisted vulnerability analysis against the Flutter client, Firebase callable functions, Firestore rules, Android/iOS platform configuration, hosting metadata, dependency locks, and authentication-related persistence. It focused on the requested login security implementation and its immediate bypass paths.',
    ), P('Methods applied', 'h2')]
    for item in [
        'Mapped every backend path that calls Firebase Admin createCustomToken.',
        'Traced registration, login, password reset, saved-session recovery, onboarding, settings, and achievement interactions.',
        'Reviewed challenge entropy, expiry, attempt limits, replay behavior, factor storage, key management, and revocation invariants.',
        'Reviewed Android/iOS passkey association prerequisites and exact bundle/package identities.',
        'Ran baseline static analysis, Flutter tests, Node tests, npm audit, signing-report inspection, and manifest/rules review.',
        'Mapped controls to OWASP MASVS-AUTH/STORAGE, OWASP WSTG MFA, NIST SP 800-63B-4, RFC 6238, and WebAuthn.',
    ]: story.append(bullet(item))
    story += [P('Assets in scope', 'h2'), styled_table([
        ['Component', 'Security role'],
        ['Flutter authentication views and view model', 'Collect identifiers and proof; must not be the sole enforcement point.'],
        ['Firebase callable functions', 'Verify factors, rate limit, and issue Firebase custom tokens.'],
        ['Firestore', 'Persist user summaries, server-only factor credentials, and one-time challenges.'],
        ['Firebase Secret Manager', 'Hold provider credentials and future TOTP encryption key.'],
        ['Android Credential Manager / iOS AuthenticationServices', 'Create and use device passkeys.'],
        ['Firebase Hosting association files', 'Bind the native apps to the passkey RP domain.'],
    ], [52 * mm, 120 * mm]), PageBreak()]
    story += [P('3. Architecture and trust boundaries', 'h1'), P(
        'Firebase ID tokens authorize most cloud data access. Accordingly, every custom-token issuer is a high-value trust boundary. A UI-only MFA prompt is insufficient if any callable still creates a token after only a password, app instance ID, or WhatsApp code.',
    ), P('Baseline trust boundaries', 'h2')]
    for item in [
        '<b>Out-of-band channel:</b> GreenAPI delivers a six-digit WhatsApp code. It proves access to a WhatsApp destination but is not phishing-resistant.',
        '<b>Firebase token issuer:</b> Callable functions use Firebase Admin to mint custom tokens. Bypass resistance must live here.',
        '<b>Local mobile state:</b> SQLite stored an appInstanceId and user session information while Android backup was enabled.',
        '<b>Future authenticator state:</b> TOTP seeds are symmetric secrets; passkeys store only public keys server-side.',
        '<b>Platform association:</b> Android signing certificates and Apple Team ID/bundle ID bind the app to the RP domain.',
    ]: story.append(bullet(item))
    story += [P('Threat actors considered', 'h2'), styled_table([
        ['Actor', 'Capability considered'],
        ['Remote credential attacker', 'Known/reused password, WhatsApp social engineering, endpoint discovery.'],
        ['Malicious or repackaged client', 'Direct callable invocation outside intended UI sequence.'],
        ['Stolen-device attacker', 'Access to copied local state or an already authenticated Firebase session.'],
        ['Network attacker', 'Replay attempts; TLS is assumed uncompromised, but protocol replay is assessed.'],
        ['Insider / data-reader', 'Read access to backend data but not Secret Manager key material.'],
    ], [45 * mm, 127 * mm]), PageBreak()]
    story += [P('4. Risk model', 'h1'), P(
        'Severity combines exploitability, authentication bypass potential, data sensitivity, and operational impact. Ratings are project-specific and are not CVSS scores.',
    ), styled_table([
        ['Severity', 'Definition'],
        ['Critical', 'Reliable compromise with broad emergency/location impact and minimal prerequisites.'],
        ['High', 'Authentication bypass or persistent account takeover with realistic prerequisites.'],
        ['Medium', 'Material defense gap, secret exposure, or sensitive-operation weakness.'],
        ['Low', 'Limited impact, deployment failure, or defense-in-depth issue.'],
        ['Info', 'Positive control, observation, or maintenance item.'],
    ], [35 * mm, 137 * mm]), P('Risk matrix', 'h2'), styled_table([
        ['Likelihood / Impact', 'Low', 'Moderate', 'High'],
        ['Likely', 'Medium', 'High', 'Critical'],
        ['Possible', 'Low', 'Medium', 'High'],
        ['Unlikely', 'Low', 'Low', 'Medium'],
    ], [48 * mm, 41 * mm, 41 * mm, 41 * mm]), PageBreak()]
    story += [P('5. Detailed findings', 'h1')]
    for i, finding in enumerate(PRE_FINDINGS):
        story += finding_block(finding)
        if i in {2, 5, 8}: story.append(PageBreak())
    story += [PageBreak(), P('6. Remediation priorities', 'h1'), styled_table([
        ['Priority', 'Action', 'Target result'],
        ['P0', 'Remove all pre-MFA custom-token issuance.', 'Only WhatsApp + TOTP/passkey can create a login token.'],
        ['P0', 'Introduce backend-owned factor enrollment and minimum-one invariant.', 'Registration cannot complete unprotected; final factor cannot be removed.'],
        ['P1', 'Implement WebAuthn with exact RP/origin validation and user verification.', 'Phishing-resistant option on Android and iOS.'],
        ['P1', 'Implement encrypted, replay-resistant RFC 6238 TOTP.', 'Compatible with Google Authenticator, Authy, and standard TOTP apps.'],
        ['P1', 'Require recent MFA for factor changes.', 'Stolen old Firebase tokens cannot alter factors.'],
        ['P2', 'Deploy association metadata, retention cleanup, and security tests.', 'Operationally usable and regression resistant.'],
    ], [22 * mm, 74 * mm, 76 * mm]), P('Acceptance criteria', 'h2')]
    for item in [
        'No unauthenticated or single-factor endpoint creates a Firebase custom token.',
        'TOTP seeds are never stored in plaintext and codes cannot be replayed in the same time step.',
        'Passkey challenges are random, one-time, expiring, and verified against exact trusted origins.',
        'At least one factor remains bound; adding/removing factors requires recent MFA after initial enrollment.',
        'Android and Apple association endpoints return HTTP 200 without redirects and JSON content type.',
        'Automated negative tests cover bypass, replay, malformed input, encryption integrity, and rules denial.',
    ]: story.append(bullet(item))
    story += [PageBreak(), P('7. Limitations', 'h1')]
    for item in [
        'The baseline was a working tree with unrelated pre-existing changes; this assessment isolates authentication evidence rather than claiming a clean release commit.',
        'No real account credentials were used for destructive or takeover testing.',
        'No physical Android or iOS device was connected. Platform ceremony testing therefore remained a release-QA requirement.',
        'The assessment did not attempt social engineering, WhatsApp provider compromise, telecom attacks, or denial of service against production.',
        'A dependency audit is time-bound and cannot prove absence of unknown vulnerabilities.',
    ]: story.append(bullet(item))
    story += [PageBreak(), P('Appendix A. Evidence and standards references', 'h1')]
    refs = [
        ('OWASP MASVS', 'https://mas.owasp.org/MASVS/'),
        ('OWASP MASVS-AUTH checklist', 'https://mas.owasp.org/checklists/MASVS-AUTH/'),
        ('OWASP WSTG MFA testing', 'https://owasp.org/www-project-web-security-testing-guide/latest/4-Web_Application_Security_Testing/04-Authentication_Testing/11-Testing_Multi-Factor_Authentication'),
        ('NIST SP 800-63B-4', 'https://pages.nist.gov/800-63-4/sp800-63b.html'),
        ('RFC 6238 TOTP', 'https://www.rfc-editor.org/info/rfc6238/'),
        ('W3C WebAuthn Level 3', 'https://www.w3.org/TR/webauthn-3/'),
        ('Android passkey creation', 'https://developer.android.com/identity/passkeys/create-passkeys'),
        ('Apple supporting passkeys', 'https://developer.apple.com/documentation/authenticationservices/supporting-passkeys'),
        ('SimpleWebAuthn server documentation', 'https://simplewebauthn.dev/docs/packages/server'),
        ('Flutter passkeys package', 'https://pub.dev/packages/passkeys'),
    ]
    story.append(styled_table([['Reference', 'URL']] + [[name, url] for name, url in refs], [52 * mm, 120 * mm]))
    doc = SecurityDoc(path, title, 'Pre-Remediation VA')
    doc.build(story)


PENTEST_CASES = [
    ['PT-01', 'Direct password token issuance', 'Call legacy password endpoint with a valid credential.', 'Code path minted a Firebase custom token after password only.', 'Fail', 'High'],
    ['PT-02', 'Saved-session recovery bypass', 'Replay phone plus bound appInstanceId.', 'Code path minted a token without WhatsApp or factor.', 'Fail', 'High'],
    ['PT-03', 'WhatsApp-only completion', 'Complete valid WhatsApp OTP and inspect response.', 'Response contained Firebase custom token; no second challenge.', 'Fail', 'High'],
    ['PT-04', 'OTP guessing control', 'Submit malformed/incorrect codes and inspect attempt state.', 'Six digits, five attempts, expiry, HMAC compare, and cooldown were present.', 'Pass', 'Info'],
    ['PT-05', 'WhatsApp OTP replay', 'Reuse a consumed or expired challenge.', 'Transaction rejected consumed/expired challenge.', 'Pass', 'Info'],
    ['PT-06', 'Factor downgrade', 'Search for a minimum factor count and deletion guard.', 'No factor registry or minimum-one invariant existed.', 'Fail', 'High'],
    ['PT-07', 'WebAuthn origin/RP verification', 'Search client/server/platform trust association.', 'WebAuthn and association metadata were absent.', 'Not implemented', 'Medium'],
    ['PT-08', 'TOTP replay and seed storage', 'Search enrollment/verification/secret storage.', 'TOTP was absent; no controls could be validated.', 'Not implemented', 'Medium'],
    ['PT-09', 'Mobile backup exposure', 'Inspect Android backup configuration and local state.', 'allowBackup=true with durable SQLite session identity.', 'Fail', 'Medium'],
    ['PT-10', 'Dependency advisory scan', 'npm audit production dependency graph.', '0 known vulnerabilities at test time.', 'Pass', 'Info'],
    ['PT-11', 'Full Flutter regression baseline', 'Run flutter test --no-pub.', 'Three unrelated existing tests failed: region filter finder and two SQLite migration tests.', 'Baseline failure', 'Low'],
]


def build_pentest_report(path):
    title = 'Pre-Remediation Penetration Test Report'
    story = []
    story += cover('Pre-Remediation\nPenetration Test', 'Controlled white-box and non-destructive endpoint testing')
    story += document_control(title, 'Authentication bypass, replay, enrollment, factor management, and platform association tests before remediation.')
    story += toc([
        ('1', 'Executive summary'), ('2', 'Rules of engagement'), ('3', 'Test environment and tooling'),
        ('4', 'Attack paths'), ('5', 'Test case results'), ('6', 'Exploit narratives'),
        ('7', 'Evidence integrity and limitations'), ('A', 'Raw result summary'),
    ])
    story += [P('1. Executive summary', 'h1'), P(
        'The controlled penetration test confirmed that the requested MFA could have been bypassed through three existing backend token issuers. This was a design-level bypass: an attacker did not need to defeat TOTP or WebAuthn because those checks were absent from the alternate token paths. Existing WhatsApp OTP attempt and replay controls performed positively, but they protected only the WhatsApp step.',
    ), risk_summary({'High': 4, 'Medium': 3, 'Low': 1, 'Info': 3}), Spacer(1, 6 * mm),
    P('<b>Outcome:</b> MFA enforcement was not present at the baseline trust boundary. The test recommendation was to redesign token issuance before conducting authenticator cryptographic tests.', 'callout'),
    auth_flow(before=True), PageBreak()]
    story += [P('2. Rules of engagement', 'h1')]
    for item in [
        '<b>Authorization:</b> project source and the Firebase project identified by the repository were in scope for implementation-oriented testing.',
        '<b>Safety:</b> no brute force, traffic flooding, credential stuffing, social engineering, emergency/SOS triggering, or destructive writes were performed.',
        '<b>Production:</b> baseline conclusions about successful token creation were confirmed by white-box path analysis rather than using another user account.',
        '<b>Data handling:</b> secret values, OTPs, GreenAPI credentials, and .env values were not printed into evidence or reports.',
        '<b>Stop conditions:</b> tests stopped at proof of bypass logic; no protected user data was accessed.',
    ]: story.append(bullet(item))
    story += [P('Assessment boundaries', 'h2'), styled_table([
        ['Included', 'Excluded'],
        ['Mobile login/register UI; callables; Firestore rules; passkey/TOTP design; local session recovery; platform metadata.', 'WhatsApp provider compromise; telecom/SIM swap; physical device extraction; production denial of service; social engineering.'],
    ], [86 * mm, 86 * mm]), PageBreak()]
    story += [P('3. Test environment and tooling', 'h1'), styled_table([
        ['Item', 'Value'],
        ['Host', 'Windows local development host; Asia/Singapore timezone.'],
        ['Mobile stack', 'Flutter / Dart; Android Gradle project; iOS Xcode project reviewed statically.'],
        ['Backend', 'Firebase Functions Node.js 22, Firestore rules, Firebase Auth custom tokens.'],
        ['Tools', 'ripgrep source tracing, Node test runner, Flutter analyzer/tests, npm audit, Gradle signingReport, HTTP probes.'],
        ['Evidence reference', BASELINE_REF],
        ['Test model', 'White-box and grey-box; non-destructive; no production credentials.'],
    ], [43 * mm, 129 * mm]), P('Baseline test observations', 'h2')]
    for item in [
        'Node test command initially used a directory target that Node 24 did not resolve; the script was corrected to execute test/*.test.js.',
        'Flutter analyzer reached the baseline successfully; later full regression testing exposed three unrelated pre-existing test failures.',
        'npm audit returned zero known vulnerabilities in the production function dependency graph.',
        'Android signingReport showed the same development/debug certificate for debug and locally signed release mode.',
    ]: story.append(bullet(item))
    story += [PageBreak(), P('4. Attack paths', 'h1'), P('Attack path A: password bypass', 'h2'), P(
        'Prerequisite: possession of a valid password. The attacker calls loginWithPassword directly, bypassing any client navigation. The function verifies Argon2, then creates a Firebase custom token. Result: second factor is not consulted.',
    ), P('Attack path B: copied saved-device credential', 'h2'), P(
        'Prerequisite: phone number and copied boundAppInstanceId from local state. The unauthenticated recovery callable checks those values and creates a token. Because Android backup was enabled, the durable identifier had a broader exposure path than intended.',
    ), P('Attack path C: WhatsApp-only login', 'h2'), P(
        'Prerequisite: access to the WhatsApp OTP. The verification transaction correctly consumes the code, but immediately returns a Firebase custom token. There is no factor-selection or factor-verification state.',
    ), P('Why a client prompt would not fix these paths', 'h2'), P(
        'A modified client can invoke callables directly. OWASP MFA testing guidance emphasizes reviewing every alternate authentication path. Enforcement must occur before token issuance on the server.',
    ), PageBreak()]
    story += [P('5. Test case results', 'h1')]
    table_data = [['ID', 'Test', 'Technique', 'Observed', 'Result', 'Risk']] + PENTEST_CASES
    story.append(styled_table(table_data, [16*mm, 30*mm, 39*mm, 53*mm, 20*mm, 14*mm], font_size=6.8))
    story += [PageBreak(), P('6. Exploit narratives', 'h1')]
    narratives = [
        ('PT-01 / PT-03: authentication-state confusion', 'The system treated successful completion of any recognized login method as sufficient to create the same Firebase session. Once MFA is introduced, each token issuer must attach to one canonical state machine. Otherwise, an older endpoint remains a downgrade oracle.'),
        ('PT-02: durable bearer-like device identifier', 'The appInstanceId was random and device-bound by application logic, but it was still a replayable shared value. It did not cryptographically prove user presence and therefore could not satisfy the requested second-factor requirement.'),
        ('PT-06: unenforced enrollment invariant', 'Without server-owned factor records, the mobile UI could neither prove enrollment nor safely manage deletion. A minimum-one invariant has to be transactional and must not depend on a displayed count.'),
        ('PT-07: platform association prerequisite', 'Passkeys require both cryptographic WebAuthn verification and native-app-to-domain association. Missing or mismatched signing identities generally cause availability failure; accepting broad origins to work around that would create a security flaw.'),
        ('PT-11: regression signal', 'The existing full Flutter suite was not clean. The failures were outside authentication, but they reduce release confidence and must be tracked separately from MFA acceptance results.'),
    ]
    for heading, body in narratives:
        story += [P(heading, 'h2'), P(body)]
    story += [PageBreak(), P('7. Evidence integrity and limitations', 'h1')]
    for item in [
        'White-box evidence establishes reachable token-issuing code paths but does not quantify real-world credential prevalence.',
        'No Firebase token was obtained for another user and no protected collection was queried during testing.',
        'No physical device was connected, so biometric prompts, device credential provider behavior, and store-signing association could not be tested.',
        'The iOS target was reviewed on Windows and could not be built with Xcode.',
        'Production provider and App Check behavior was not stress-tested.',
    ]: story.append(bullet(item))
    story += [PageBreak(), P('Appendix A. Raw result summary', 'h1'), styled_table([
        ['Command / check', 'Baseline result'],
        ['flutter analyze --no-pub', 'Completed; later post-change analyzer also reported no issues.'],
        ['flutter test --no-pub', 'Three unrelated existing failures; remainder progressed to 162 tests with 159 passing.'],
        ['npm test (after test-script correction)', 'Existing helper suite passed; MFA-specific tests did not exist at baseline.'],
        ['npm audit --json / --omit=dev', '0 known vulnerabilities.'],
        ['Gradle signingReport', 'Development SHA-256 73:6F:D0:E3:...:96:5E for local debug/release.'],
        ['Platform association files', 'Absent at baseline.'],
        ['Physical-device ceremony', 'Not executed: no Android/iOS device connected.'],
    ], [58 * mm, 114 * mm]), P('Retest requirement', 'h2'), P(
        'After remediation, repeat direct endpoint probes, replay tests, factor-removal tests, association HTTP checks, dependency audit, analyzer, targeted widget tests, Android build, and physical Android/iOS passkey ceremonies using final store signing identities.',
    )]
    doc = SecurityDoc(path, title, 'Pre-Remediation Pentest')
    doc.build(story)


POST_CONTROLS = [
    ['C-01', 'Canonical two-step login state', 'WhatsApp verification returns only a hashed, 256-bit opaque MFA session; no Firebase token.', 'Implemented / deployed'],
    ['C-02', 'Mandatory enrollment gate', 'New and factorless legacy users must bind TOTP or passkey before token issuance.', 'Implemented / deployed'],
    ['C-03', 'RFC 6238 TOTP', '160-bit seed; SHA-1; six digits; 30-second period; +/-1 step; last-used-step replay block.', 'Implemented / tested'],
    ['C-04', 'TOTP encryption', 'AES-256-GCM with AAD; encryption key stored in Firebase Secret Manager.', 'Implemented / deployed'],
    ['C-05', 'WebAuthn passkeys', 'Exact RP ID; origin allowlist; required user verification; one-time challenges; counters.', 'Implemented / deployed'],
    ['C-06', 'Android association', 'Digital Asset Links for package and current signing certificate; JSON/200 endpoint.', 'Implemented / live'],
    ['C-07', 'Apple association', 'webcredentials entitlement plus Team ID/bundle AASA; JSON/200 endpoint.', 'Implemented / live'],
    ['C-08', 'Factor management', 'Recent MFA (10 minutes) for add/remove; server rejects deletion of final factor.', 'Implemented / deployed'],
    ['C-09', 'Server-only factor data', 'Explicit Firestore deny rules for factors, sessions, and challenges.', 'Implemented / deployed'],
    ['C-10', 'Legacy bypass retirement', 'Password-only and saved-device recovery callables return FAILED_PRECONDITION.', 'Implemented / live probe'],
    ['C-11', 'Retention and throttling', 'Five WebAuthn attempts; bounded TOTP attempts; daily expired-artifact cleanup.', 'Implemented / deployed'],
    ['C-12', 'Mobile backup reduction', 'Android application backup disabled.', 'Implemented / build verified'],
    ['C-13', 'Achievement integration', 'Security Guardian progress records each distinct TOTP/passkey type once.', 'Implemented'],
]


def build_post_report(path):
    title = 'Post-Remediation Security Implementation and Retest Report'
    story = []
    story += cover('Post-Remediation\nSecurity Report', 'Implementation, vulnerability reassessment, and penetration retest')
    story += document_control(title, 'Implemented WhatsApp + TOTP/passkey mobile MFA, remediation verification, deployment evidence, and residual risk.')
    story += toc([
        ('1', 'Executive summary'), ('2', 'Implemented architecture'), ('3', 'Control implementation'),
        ('4', 'Finding remediation matrix'), ('5', 'Penetration retest results'), ('6', 'Build and deployment evidence'),
        ('7', 'Residual risks and release gates'), ('8', 'Operations and incident guidance'), ('A', 'Standards mapping'),
    ])
    story += [P('1. Executive summary', 'h1'), P(
        'HikerCircle now enforces WhatsApp plus one bound secondary method before issuing a Firebase login token. Users may bind a standard six-digit TOTP Authenticator or a platform passkey. Initial registration cannot complete without one method, settings cannot remove the final method, and binding both advances the Security Guardian achievement.',
    ), auth_flow(before=False), Spacer(1, 5 * mm),
    P('<b>Post-remediation risk: Moderate residual release risk.</b> The identified backend MFA bypasses are closed and live probes confirm the legacy endpoints reject token issuance. The remaining material gate is physical-device validation with final Android Play signing and an iOS build from Xcode.', 'callout'),
    risk_summary({'Critical': 0, 'High': 0, 'Medium': 2, 'Low': 3, 'Info': 4}), PageBreak()]
    story += [P('2. Implemented architecture', 'h1'), P('Login sequence', 'h2')]
    sequence = [
        ['Step', 'Server/client behavior', 'Security property'],
        ['1', 'User selects Sign Up or Login and requests WhatsApp OTP.', 'Intent and account existence are checked before delivery.'],
        ['2', 'GreenAPI sends a six-digit code; backend stores only HMAC of the code.', 'Five attempts, five-minute expiry, one-minute resend cooldown.'],
        ['3', 'Correct WhatsApp code creates a random MFA session; no Firebase token.', 'Pre-auth state is hashed at rest, ten-minute expiry, eight TOTP attempts.'],
        ['4a', 'TOTP: verify current Authenticator code.', 'RFC 6238, narrow clock window, timing-safe compare, replayed step rejected.'],
        ['4b', 'Passkey: verify signed WebAuthn challenge.', 'RP/origin binding, required user verification, counter and challenge replay controls.'],
        ['5', 'Backend consumes session and creates Firebase custom token with MFA claims.', 'Only the canonical two-step path reaches protected Firebase data.'],
    ]
    story += [styled_table(sequence, [13*mm, 89*mm, 70*mm]), P('Enrollment and lifecycle', 'h2')]
    for item in [
        'New account records are created when the first factor is successfully bound, preventing unprotected partial accounts from receiving a session.',
        'Legacy accounts with no factors are migrated through the same mandatory enrollment gate on their next WhatsApp login.',
        'TOTP seeds are returned once for setup, encrypted before Firestore storage, and protected by a Secret Manager key that is not included in source or the app.',
        'Passkey private keys remain in the platform credential provider; Firestore stores the credential public key, identifier, counter, transports, device type, backup flag, and AAGUID.',
        'Factor add/remove operations require a recent MFA-authenticated Firebase token; deletion is rejected when only one factor remains.',
        'Expired sessions and challenges are removed every 24 hours; successful TOTP enrollment deletes the temporary encrypted seed.',
    ]: story.append(bullet(item))
    story += [PageBreak(), P('3. Control implementation', 'h1'), styled_table([['ID', 'Control', 'Implementation evidence', 'Status']] + POST_CONTROLS, [14*mm, 40*mm, 91*mm, 27*mm], font_size=6.7), PageBreak()]
    story += [P('4. Finding remediation matrix', 'h1')]
    remap = [
        ['Finding', 'Baseline', 'Remediation', 'Residual'],
        ['VA-01', 'Password-only token', 'Endpoint now fails before credential processing; login UI uses WhatsApp + factor.', 'Closed'],
        ['VA-02', 'Saved-device token recovery', 'Endpoint now returns FAILED_PRECONDITION and forces fresh two-step login.', 'Closed'],
        ['VA-03', 'WhatsApp-only token', 'Returns opaque MFA session; regression test asserts no createCustomToken in block.', 'Closed'],
        ['VA-04', 'No mandatory factor', 'Backend enrollment gate and minimum-one removal invariant.', 'Closed'],
        ['VA-05', 'No passkey association', 'WebAuthn verifier, DAL, AASA, entitlements, exact origins deployed.', 'Low: final store certificates/device QA'],
        ['VA-06', 'No TOTP lifecycle', 'RFC 6238 helper, AES-GCM, Secret Manager, replay and attempt controls.', 'Low: TOTP remains phishable'],
        ['VA-07', 'Android backup enabled', 'allowBackup=false.', 'Closed'],
        ['VA-08', 'No recent-MFA factor rule', 'mfa claim plus auth_time <=10 minutes.', 'Closed'],
        ['VA-09', 'No production signing origin', 'Current development origin live.', 'Medium until Play signing fingerprint supplied'],
        ['VA-10', 'No artifact retention/attempt design', 'Five WebAuthn attempts and scheduled cleanup.', 'Closed'],
        ['VA-11', 'Dependency audit', 'Re-run: zero known vulnerabilities.', 'Monitor'],
    ]
    story += [styled_table(remap, [17*mm, 43*mm, 82*mm, 30*mm], font_size=6.7), PageBreak()]
    story += [P('5. Penetration retest results', 'h1')]
    retests = [
        ['Test', 'Retest method', 'Observed result', 'Status'],
        ['RT-01 WhatsApp pre-auth token', 'Static regression extracts verifyGreenApiLoginCode block.', 'No createCustomToken; MFA session reference present.', 'Pass'],
        ['RT-02 password bypass', 'Live callable POST with non-secret dummy input.', 'HTTP 400 / FAILED_PRECONDITION.', 'Pass'],
        ['RT-03 saved-session bypass', 'Live callable POST with dummy input.', 'HTTP 400 / FAILED_PRECONDITION.', 'Pass'],
        ['RT-04 unauthenticated factor status', 'Live callable POST without Firebase auth.', 'HTTP 401 / UNAUTHENTICATED.', 'Pass'],
        ['RT-05 bogus TOTP session', 'Live callable with syntactically valid fake token.', 'HTTP 504 callable error / DEADLINE_EXCEEDED; no token.', 'Pass'],
        ['RT-06 TOTP replay', 'Unit test accepted a current step then resubmitted same code.', 'Second submission rejected.', 'Pass'],
        ['RT-07 TOTP stale/future/malformed', 'Unit tests outside +/-1 and malformed code.', 'All rejected.', 'Pass'],
        ['RT-08 TOTP encryption integrity', 'Wrong key and modified ciphertext tests.', 'Decryption/authentication failed.', 'Pass'],
        ['RT-09 random challenge collision', 'Generated 2,000 256-bit opaque tokens.', '2,000 unique; minimum 43 Base64URL characters.', 'Pass'],
        ['RT-10 WebAuthn policy', 'Static regression checks RP, exact origins, UV flags.', 'Exact RP; no wildcard; UV required in options and verification.', 'Pass'],
        ['RT-11 Firestore direct access', 'Rules source and deploy compiler.', 'Explicit allow read, write: if false for factor/session collections.', 'Pass'],
        ['RT-12 native passkey ceremony', 'Physical Android/iOS device.', 'Not executable: no device connected; release gate remains.', 'Pending'],
    ]
    story += [styled_table(retests, [22*mm, 52*mm, 70*mm, 28*mm], font_size=6.8), P('Regression test totals', 'h2')]
    for item in [
        '<b>Node backend:</b> 53 tests passed, 0 failed, including seven MFA security regression tests.',
        '<b>Flutter targeted:</b> 2 MFA enrollment/login UI tests passed.',
        '<b>Flutter analyzer:</b> no issues found.',
        '<b>Android:</b> debug APK built successfully with the passkey plugin.',
        '<b>Dependencies:</b> npm audit found 0 known vulnerabilities.',
        '<b>Full Flutter suite:</b> 159 passed and 3 unrelated pre-existing tests failed; not counted as MFA failures.',
    ]: story.append(bullet(item))
    story += [PageBreak(), P('6. Build and deployment evidence', 'h1'), styled_table([
        ['Evidence', 'Result'],
        ['Firebase Secret Manager', 'MFA_TOTP_ENCRYPTION_KEY version 1 created; compute service account granted accessor role. Secret value not logged or stored in repository.'],
        ['Cloud Functions', 'Nine MFA callables plus daily cleanup deployed; legacy login/recovery revisions deployed.'],
        ['Firestore rules', 'Compiled successfully and released; factor/session/challenge collections explicitly denied.'],
        ['Firebase Hosting', 'Association files deployed at hiker-circle.web.app.'],
        ['Android DAL probe', 'HTTP 200; application/json; one-hour public cache.'],
        ['Apple AASA probe', 'HTTP 200; application/json; one-hour public cache; no redirect observed.'],
        ['Android build', 'build/app/outputs/flutter-apk/app-debug.apk created successfully.'],
        ['iOS configuration', 'Minimum iOS 16; webcredentials entitlement for hiker-circle.web.app; Team ID L688FNL4LW and exact bundle ID recorded.'],
    ], [47*mm, 125*mm]), P('Deployment note', 'h2'), P(
        'The first function discovery attempt exceeded the Firebase CLI default ten-second discovery window because the project contains a large monolithic functions index. The deployment was repeated with a 60-second discovery timeout and completed. One temporary mutation-quota retry was automatically recovered by the CLI.',
    ), PageBreak()]
    story += [P('7. Residual risks and release gates', 'h1')]
    residual = [
        ['ID', 'Residual risk', 'Rating', 'Required action'],
        ['R-01', 'Play App Signing uses a certificate not yet supplied to this workspace. A mismatched DAL/origin will make passkeys fail in store builds.', 'Medium', 'Add Play App Signing SHA-256 to assetlinks.json and base64url apk-key-hash to MFA_EXPECTED_ORIGINS; redeploy; test Play internal track.'],
        ['R-02', 'No physical Android or iOS passkey ceremony was executed.', 'Medium', 'Run the release checklist on at least two Android API 28+ devices and iOS 16+ physical devices using production signing.'],
        ['R-03', 'TOTP and WhatsApp codes can be phished or relayed; they are not verifier-bound.', 'Low', 'Prefer passkey in UI and education; monitor suspicious sign-in and factor-change events.'],
        ['R-04', 'Loss of the sole bound factor can lock the account; insecure recovery would weaken MFA.', 'Low', 'Design a separately reviewed recovery process (support proofing or recovery codes) before launch. Do not re-enable password-only recovery.'],
        ['R-05', 'App Check enforcement is not enabled on these auth callables due earlier device attestation failures.', 'Low', 'After production App Check is stable, enforce it as defense in depth without treating it as an authentication factor.'],
        ['R-06', 'Client API keys in .env are packaged by design for mobile map/routing features.', 'Low', 'Apply provider-side Android/iOS/API restrictions and quotas; proxy any key that grants server-level privileges.'],
        ['R-07', 'Three unrelated full-suite Flutter tests remain red.', 'Low', 'Resolve region-filter finder and SQLite v20/v21 migration fixtures before release.'],
    ]
    story += [styled_table(residual, [14*mm, 73*mm, 20*mm, 65*mm], font_size=6.7), P('Release decision', 'h2'), P(
        '<b>Conditionally ready for mobile release testing.</b> Backend MFA enforcement and deployment checks pass. Production distribution should remain blocked until R-01 and R-02 are completed with final store signing identities.', 'callout'), PageBreak()]
    story += [P('8. Operations and incident guidance', 'h1')]
    ops = [
        ('Factor loss', 'Do not delete the final factor through an administrative client. Verify identity through an approved recovery procedure, revoke affected credentials, and record the event.'),
        ('Suspected TOTP compromise', 'Remove/replace the TOTP factor only after recent MFA, invalidate active Firebase refresh tokens, and review sign-in/factor audit events.'),
        ('Lost passkey device', 'Remove the specific credential while retaining another factor, revoke Firebase refresh tokens if compromise is suspected, and advise removal from the platform credential provider.'),
        ('Signing certificate change', 'Update Digital Asset Links and server Android origin allowlist before distributing the newly signed app. Maintain overlap while both versions are active.'),
        ('TOTP encryption-key rotation', 'Implement decrypt-old/encrypt-new migration with versioned key references before disabling the previous Secret Manager version.'),
        ('Provider outage', 'Do not bypass MFA. Present a clear retry state and emergency support guidance; preserve already authenticated sessions according to policy.'),
    ]
    for heading, body in ops:
        story += [P(heading, 'h2'), P(body)]
    story += [PageBreak(), P('Appendix A. Standards mapping', 'h1'), styled_table([
        ['Reference', 'Implemented mapping'],
        ['RFC 6238', 'Six-digit SHA-1 TOTP; 30-second time step; at most one-step network-delay window.'],
        ['W3C WebAuthn', 'Random challenge, RP ID, exact origin verification, public-key credential verification, signature counter.'],
        ['NIST SP 800-63B-4', 'Replay-resistant OTP/cryptographic authenticators; passkey option provides phishing resistance through verifier-name binding; online attempt limits.'],
        ['OWASP MASVS-AUTH-1', 'Server-enforced authentication protocol and removal of alternate MFA bypass paths.'],
        ['OWASP MASVS-AUTH-3', 'Recent MFA required for adding/removing authenticators.'],
        ['OWASP MASVS-STORAGE / MASWE-0003', 'TOTP encryption key in Secret Manager; passkey private key remains in platform credential provider; Android backup disabled.'],
        ['OWASP WSTG-ATHN-11', 'Every token issuer and alternate login/recovery endpoint reviewed for MFA bypass.'],
        ['Android passkey prerequisites', 'Digital Asset Links and signing-certificate origin allowlist.'],
        ['Apple passkey support', 'Associated Domains webcredentials entitlement and AASA application identifier.'],
    ], [54*mm, 118*mm]), P('Reference URLs', 'h2')]
    for name, url in [
        ('NIST SP 800-63B-4', 'https://pages.nist.gov/800-63-4/sp800-63b.html'),
        ('RFC 6238', 'https://www.rfc-editor.org/info/rfc6238/'),
        ('W3C WebAuthn Level 3', 'https://www.w3.org/TR/webauthn-3/'),
        ('OWASP MASVS', 'https://mas.owasp.org/MASVS/'),
        ('OWASP WSTG MFA', 'https://owasp.org/www-project-web-security-testing-guide/latest/4-Web_Application_Security_Testing/04-Authentication_Testing/11-Testing_Multi-Factor_Authentication'),
        ('Android passkeys', 'https://developer.android.com/identity/passkeys/create-passkeys'),
        ('Apple passkeys', 'https://developer.apple.com/documentation/authenticationservices/supporting-passkeys'),
    ]:
        story.append(P(f'<b>{name}:</b> {url}', 'small'))
    doc = SecurityDoc(path, title, 'Post-Remediation Security')
    doc.build(story)


def main():
    outputs = [
        os.path.join(OUT, 'HikerCircle_Pre_Remediation_Vulnerability_Assessment.pdf'),
        os.path.join(OUT, 'HikerCircle_Pre_Remediation_Penetration_Test.pdf'),
        os.path.join(OUT, 'HikerCircle_Post_Remediation_Security_Report.pdf'),
    ]
    build_vulnerability_report(outputs[0])
    build_pentest_report(outputs[1])
    build_post_report(outputs[2])
    for path in outputs:
        print(f'{path}|{os.path.getsize(path)}')


if __name__ == '__main__':
    main()
