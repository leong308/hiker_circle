// Public beta download state, release metadata, and platform-specific installation help.
"use strict";
  const loadBetaDownload = async () => {
    const link = document.querySelector('[data-beta-download]');
    if (!link) return;
    try {
      const response = await fetch('/site/beta-release.json', { cache: 'no-cache' });
      if (!response.ok) throw new Error('Release unavailable');
      const release = await response.json();
      const url = new URL(release.url);
      if (url.protocol !== 'https:' || url.hostname !== 'firebasestorage.googleapis.com' ||
          !url.pathname.startsWith('/v0/b/hiker-circle.firebasestorage.app/o/releases%2Fandroid%2Fbeta%2F') ||
          !/^[a-f0-9]{64}$/.test(release.sha256) || !Number.isFinite(release.sizeBytes) || release.sizeBytes <= 0) throw new Error('Invalid release');
      link.href = url.href;
      link.removeAttribute('aria-disabled');
      link.textContent = 'Download Android beta ↓';
      document.querySelector('[data-beta-size]').textContent = `${(release.sizeBytes / 1048576).toFixed(1)} MB · Direct APK download`;
    } catch (_) {
      link.textContent = 'Download temporarily unavailable';
    }
  };


loadBetaDownload();

(() => {
  const explorer = document.querySelector('.beta-explorer');
  if (!explorer) return;
  const tabs = [...explorer.querySelectorAll('[role="tab"]')];
  const panels = [...explorer.querySelectorAll('[role="tabpanel"]')];
  let current = 0;
  const select = (index, focus = false) => {
    current = (index + tabs.length) % tabs.length;
    tabs.forEach((tab, i) => {
      tab.setAttribute('aria-selected', String(i === current));
      tab.tabIndex = i === current ? 0 : -1;
      panels[i].hidden = i !== current;
    });
    explorer.querySelector('[data-beta-position]').textContent = `0${current + 1} / 04`;
    if (focus) tabs[current].focus();
  };
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => select(index));
    tab.addEventListener('keydown', event => {
      const target = { ArrowRight: current + 1, ArrowLeft: current - 1, Home: 0, End: tabs.length - 1 }[event.key];
      if (target === undefined) return;
      event.preventDefault(); select(target, true);
    });
  });
  explorer.querySelector('[data-beta-prev]').addEventListener('click', () => select(current - 1));
  explorer.querySelector('[data-beta-next]').addEventListener('click', () => select(current + 1));
  let touch = null;
  const stage = explorer.querySelector('.beta-feature-stage');
  stage.addEventListener('pointerdown', event => {
    if (event.pointerType === 'touch') touch = { x: event.clientX, y: event.clientY };
  });
  stage.addEventListener('pointercancel', () => { touch = null; });
  stage.addEventListener('pointerup', event => {
    if (!touch) return;
    const dx = event.clientX - touch.x, dy = event.clientY - touch.y;
    touch = null;
    if (Math.abs(dx) > 55 && Math.abs(dx) > Math.abs(dy) * 1.5) select(current + (dx < 0 ? 1 : -1));
  });
})();
