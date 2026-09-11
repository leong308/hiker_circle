import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('landing site presents the complete HikerCircle evolution timeline', () {
    final page = File('web/index.html').readAsStringSync();

    expect(page, contains('href="#evolution"'));
    expect(page, contains('id="evolution"'));
    expect(page, contains('1 September 2026'));
    expect(page, isNot(contains('evolution-facts')));
    expect(page, isNot(contains('Development commits reviewed')));
    expect(page, isNot(contains('Based on the complete repository history')));
    expect(page, contains('Still evolving with every trail'));
    expect(RegExp('data-evolution-card').allMatches(page), hasLength(13));
    expect(page, contains('datetime="2026-09-07">7 September 2026'));
    expect(page, contains('Every adventure comes into focus'));
    expect(page.indexOf('data-milestone="trail-confidence"'),
        lessThan(page.indexOf('data-milestone="future"')));
    expect(RegExp(r'<time[^>]*>[^<]*–').hasMatch(page), isFalse);
    expect(page, contains('datetime="2026-05-28">28 May 2026'));
    expect(page, contains('datetime="2026-08-28">28 August 2026'));
    expect(page, contains('data-evolution-total>13'));
    expect(page, contains('The circle reaches farther'));
    expect(page, contains('smartwatches'));
    expect(page, contains('LoRa gateways'));
    expect(page, contains('mesh connections'));
    expect(page, contains('Home-screen widgets and Live Activities'));
    expect(RegExp('data-milestone-open=').allMatches(page), hasLength(13));
    expect(page, contains('data-milestone-dialog'));
    expect(page, contains('aria-modal="true"'));
    expect(page, contains('Screenshot slot'));
    expect(page, contains('Screen recording slot'));
    expect(page, contains('data-milestone-shot-media'));
    expect(page, contains('data-milestone-shot-image'));
    expect(page, contains('data-milestone-motion-media'));
    expect(page, contains('data-milestone-motion-video'));
    expect(page, contains('data-milestone-video-toggle'));
    final downloadPage = File('web/get-app.html').readAsStringSync();
    expect(page, isNot(contains('id="get-app"')));
    expect(page, contains('class="showcase-download"'));
    expect(page, contains('href="/get-app"'));
    expect(downloadPage, contains('id="get-app"'));
    expect(page, contains('id="trail-totals"'));
    expect(RegExp('data-trail-stat=').allMatches(page), hasLength(6));
    expect(page, contains('Combined trail distance'));
    expect(downloadPage, contains('data-beta-download'));
    expect(downloadPage, contains('ANDROID BETA'));
    expect(RegExp('class="store-lock-overlay"').allMatches(downloadPage), hasLength(2));
    expect(page, isNot(contains('qr-redacted')));
    expect(File('web/site/steel-chains-overlay.png').existsSync(), isTrue);
    expect(downloadPage, contains('Keep Play Protect enabled'));
    expect(page, contains('data-future-lab hidden'));
    expect(RegExp('data-future-step=').allMatches(page), hasLength(4));
    expect(page, contains('No real messages are sent'));
    expect(page, contains('No release date or full-coverage guarantee'));

    final evolution = page.substring(
      page.indexOf('id="evolution"'),
      page.indexOf('id="journey"'),
    );
    for (final technicalTerm in [
      'Firebase',
      'bottom navigation',
      'persistent sessions',
      'deep-link',
      'native background',
      'GPS tracking',
      'BLE',
      'replay protection',
      'server-backed',
      'regression coverage',
      'WebAuthn',
      'encrypted secrets',
    ]) {
      expect(evolution, isNot(contains(technicalTerm)), reason: technicalTerm);
    }
  });

  test('evolution timeline supports pointer, keyboard, and touch scrolling', () {
    final script = File('web/site/app.js').readAsStringSync();
    final styles = File('web/site/styles.css').readAsStringSync();
    expect(styles, contains('grid-template-columns: repeat(3, minmax(0, 1fr)); grid-auto-rows: 1fr'));
    expect(styles, isNot(contains('.download-beta { grid-column: 1 / -1; }')));

    expect(script, contains('data-evolution-rail'));
    expect(script, contains('pointerdown'));
    expect(script, contains('ArrowLeft'));
    expect(script, contains('ArrowRight'));
    expect(styles, contains('-webkit-overflow-scrolling: touch'));
    expect(styles, contains('scroll-snap-type: x mandatory'));
    expect(styles, contains('.evolution-card-future { opacity: .72'));
    expect(styles, contains('border-style: dashed'));
    expect(styles, contains('touch-action: pan-x'));
    expect(styles, contains('.milestone-dialog'));
    expect(styles, contains('.milestone-media-grid'));
    expect(styles, contains('.milestone-media-slot.has-media'));
    expect(styles, contains('.milestone-media-grid.has-single-media'));
    expect(styles, contains('scrollbar-width: none'));
    expect(
      styles,
      contains('.milestone-dialog-panel::-webkit-scrollbar'),
    );
    expect(script, contains('const milestoneStories = ['));
    expect(script, contains('Home-screen SOS widgets'));
    expect(script, contains('Live Activities'));
    expect(script, contains('renderMilestone'));
    expect(script, contains('resetFutureConcept'));
    expect(script, contains('No connection. No delivery claim.'));
    expect(styles, contains('.milestone-media-grid[hidden] { display: none; }'));
    expect(script, contains('event.key === "Escape"'));
    expect(script, contains('suppressMilestoneOpen'));
    expect(
      script,
      contains('/site-assets/evolution/01-foundation-first-sos-iphone.png'),
    );
    expect(script, contains('mediaGrid?.classList.toggle("has-single-media"'));
    expect(script, contains('mediaGrid?.classList.toggle("has-media-pair"'));
    expect(script, contains('milestoneVideoToggle?.addEventListener'));
    expect(
      script,
      isNot(contains('Captured from the 28 May 2026 interface')),
    );
    expect(
      File(
        'web/site-assets/evolution/01-foundation-first-sos-iphone.png',
      ).existsSync(),
      isTrue,
    );
    for (final asset in [
      '02-companion-walkthrough-iphone.mp4',
      '02-companion-walkthrough-poster-iphone.png',
      '03-active-safety-surfaces-iphone.png',
      '03-active-safety-response-iphone.mp4',
      '03-active-safety-response-poster-iphone.png',
      '04-coordination-team-launch-iphone.jpeg',
      '04-coordination-team-flow-poster-iphone.jpeg',
      '04-coordination-team-flow-iphone.mp4',
    ]) {
      expect(
        File('web/site-assets/evolution/$asset').existsSync(),
        isTrue,
        reason: asset,
      );
    }
    expect(
      styles,
      contains(
        '.evolution-card.is-current::before { background: var(--amber); box-shadow: 0 0 0 5px rgba(229,140,44,.14); transform: translate(-50%,8px); }',
      ),
    );
  });
}
