(() => {
  'use strict';
  const $ = (selector) => document.querySelector(selector);
  const base = '/internal/app-showcase/';
  const viewer = $('#viewer');
  let catalog;
  let chapter = 'all';
  let filtered = [];
  let current = null;
  let stepIndex = 0;
  let returnFocus = null;
  let toastTimer;

  const element = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  };
  const chapterName = (id) => catalog.chapters.find((entry) => entry.id === id)?.title || '';
  const hasMedia = (item) => Boolean(item.image || item.video);
  const sourceLabel = (item) => item.source === 'preview' ? 'Interface preview' : item.source === 'needed' ? 'Capture needed' : item.chapter === 'archive' ? 'Archive / staged' : /staged demonstration/i.test(item.notes || '') ? 'Staged demo' : 'Existing app capture';

  function flowArtwork(item, selected = -1, label = 'FLOW WALKTHROUGH · SCREEN CAPTURE PENDING') {
    const art = element('div', 'flow-art');
    art.append(element('span', '', label));
    const list = element('ol');
    item.flow.forEach((step, index) => list.append(element('li', index === selected ? 'active' : '', step)));
    art.append(list);
    return art;
  }

  function renderChapters() {
    const nav = $('#chapters');
    nav.replaceChildren();
    [{ id: 'all', title: 'All features' }, ...catalog.chapters].forEach((entry) => {
      const button = element('button', 'chapter-button');
      button.type = 'button';
      button.dataset.chapter = entry.id;
      button.setAttribute('aria-pressed', String(chapter === entry.id));
      button.append(element('span', '', entry.title), element('span', '', String(entry.id === 'all' ? catalog.items.length : catalog.items.filter((item) => item.chapter === entry.id).length).padStart(2, '0')));
      button.addEventListener('click', () => {
        chapter = entry.id;
        nav.querySelectorAll('button').forEach((node) => node.setAttribute('aria-pressed', String(node.dataset.chapter === chapter)));
        renderGallery();
      });
      nav.append(button);
    });
  }

  function renderGallery() {
    const query = $('#search').value.toLocaleLowerCase().trim();
    const filter = $('#media-filter').value;
    filtered = catalog.items.filter((item) => {
      if (chapter !== 'all' && item.chapter !== chapter) return false;
      if (filter === 'visual' && !hasMedia(item)) return false;
      if (filter === 'video' && !item.video) return false;
      if (filter === 'needed' && hasMedia(item)) return false;
      return [item.title, item.description, chapterName(item.chapter), ...item.flow].join(' ').toLocaleLowerCase().includes(query);
    });
    $('#library-title').textContent = chapter === 'all' ? 'The feature library.' : chapterName(chapter) + '.';
    $('#results-summary').textContent = `${filtered.length} of ${catalog.items.length} features · Select a card for the full screen and flow`;
    const gallery = $('#gallery');
    gallery.replaceChildren();
    $('#empty-state').hidden = filtered.length > 0;
    filtered.forEach((item) => {
      const card = element('article', 'feature-card');
      const visual = element('button', 'card-visual');
      visual.type = 'button';
      visual.setAttribute('aria-label', `Open ${item.title} walkthrough`);
      if (item.image) {
        const img = element('img');
        img.src = item.image;
        img.alt = `${item.title} — ${sourceLabel(item).toLocaleLowerCase()}`;
        img.loading = 'lazy';
        img.decoding = 'async';
        img.addEventListener('error', () => img.replaceWith(flowArtwork(item, -1, 'VISUAL UNAVAILABLE · EXPLORE THE FLOW')), { once: true });
        visual.append(img);
      } else {
        visual.append(flowArtwork(item));
      }
      if (item.video) visual.append(element('span', 'video-indicator', '▶ Recording'));
      visual.addEventListener('click', () => openFeature(item, visual));
      const body = element('div', 'card-body');
      body.append(element('div', 'card-kicker', chapterName(item.chapter)), element('h3', '', item.title), element('p', '', item.description));
      const footer = element('div', 'card-footer');
      const open = element('button', 'card-open', 'View flow ↗');
      open.type = 'button';
      open.setAttribute('aria-label', `View ${item.title} flow`);
      open.addEventListener('click', () => openFeature(item, open));
      footer.append(element('span', `source-badge ${hasMedia(item) ? '' : 'needed'}`, sourceLabel(item)), open);
      body.append(footer);
      card.append(visual, body);
      gallery.append(card);
    });
  }

  function setMedia(item, media) {
    const container = $('#viewer-media');
    container.querySelector('video')?.pause();
    container.replaceChildren();
    $('#media-tabs').querySelectorAll('button').forEach((button) => button.setAttribute('aria-pressed', String(button.dataset.media === media.id)));
    if (media.type === 'video') {
      const video = element('video');
      video.src = media.src;
      if (item.image) video.poster = item.image;
      video.controls = true;
      video.playsInline = true;
      video.preload = 'none';
      video.setAttribute('aria-label', `${item.title} screen recording`);
      video.addEventListener('error', () => {
        container.replaceChildren(flowArtwork(item, stepIndex, 'RECORDING UNAVAILABLE · EXPLORE THE FLOW'));
      }, { once: true });
      video.append(element('p', '', 'Your browser does not support this recording.'));
      container.append(video);
    } else if (media.type === 'image') {
      const image = element('img');
      image.src = media.src;
      image.alt = `${item.title}: ${media.label}`;
      image.addEventListener('error', () => {
        container.replaceChildren(flowArtwork(item), element('p', 'load-error', 'Image unavailable. The feature flow is shown instead.'));
      }, { once: true });
      container.append(image);
    } else container.append(flowArtwork(item, stepIndex));
  }

  function featureUrl(id) {
    const url = new URL(location.href);
    url.searchParams.set('feature', id);
    return url;
  }

  function setStep(index) {
    if (!current) return;
    stepIndex = Math.max(0, Math.min(index, current.flow.length - 1));
    $('#flow-position').textContent = `Step ${stepIndex + 1} of ${current.flow.length}`;
    $('#viewer-flow').querySelectorAll('button').forEach((button, i) => {
      button.setAttribute('aria-current', i === stepIndex ? 'step' : 'false');
    });
    $('#step-progress').querySelectorAll('button').forEach((button, i) => {
      button.setAttribute('aria-current', i === stepIndex ? 'step' : 'false');
    });
    $('#previous-step').disabled = stepIndex === 0;
    $('#next-step').disabled = stepIndex === current.flow.length - 1;
    if (!current.image && !current.video && !(current.images || []).length) {
      $('#viewer-media').replaceChildren(flowArtwork(current, stepIndex));
    }
  }

  function openFeature(item, trigger, updateUrl = true) {
    if (updateUrl) {
      const url = featureUrl(item.id);
      if (viewer.open) history.replaceState(history.state, '', url);
      else history.pushState({ ...history.state, showcaseFeature: true }, '', url);
    }
    current = item;
    stepIndex = 0;
    if (!viewer.open) returnFocus = trigger || document.activeElement;
    const index = filtered.findIndex((entry) => entry.id === item.id);
    $('#viewer-position').textContent = `${String(index + 1).padStart(2, '0')} / ${String(filtered.length).padStart(2, '0')} · FEATURE WALKTHROUGH`;
    $('#viewer-chapter').textContent = chapterName(item.chapter).toUpperCase();
    $('#viewer-title').textContent = item.title;
    $('#viewer-description').textContent = item.description;
    $('#viewer-source').textContent = sourceLabel(item);
    $('#viewer-flow').replaceChildren(...item.flow.map((step, index) => {
      const row = element('li');
      const button = element('button', 'flow-step', step);
      button.type = 'button';
      button.addEventListener('click', () => setStep(index));
      row.append(button);
      return row;
    }));
    const progress = $('#step-progress');
    progress.replaceChildren(...item.flow.map((_, index) => {
      const button = element('button', '', String(index + 1));
      button.type = 'button';
      button.setAttribute('aria-label', `Go to step ${index + 1}`);
      button.addEventListener('click', () => setStep(index));
      return button;
    }));
    $('#viewer-note').textContent = item.notes || '';
    $('#viewer-note').hidden = !item.notes;
    $('#viewer-capture-text').textContent = item.capture;
    $('#viewer-capture-file').textContent = item.captureFile;
    $('.viewer-capture').open = false;
    $('#previous-feature').disabled = index <= 0;
    $('#next-feature').disabled = index >= filtered.length - 1;
    const media = [];
    if (item.image) media.push({ id: 'image', type: 'image', label: 'Screenshot', src: item.image });
    (item.images || []).forEach((image, index) => media.push({ id: `image-${index}`, type: 'image', label: image.label, src: image.src }));
    if (item.video) media.push({ id: 'video', type: 'video', label: 'Recording', src: item.video });
    if (!media.length) media.push({ id: 'flow', type: 'flow', label: 'Flow walkthrough' });
    $('#media-tabs').replaceChildren();
    $('#media-tabs').hidden = media.length < 2;
    media.forEach((entry) => {
      const button = element('button', '', entry.label);
      button.type = 'button';
      button.dataset.media = entry.id;
      button.setAttribute('aria-pressed', 'false');
      button.addEventListener('click', () => setMedia(item, entry));
      $('#media-tabs').append(button);
    });
    setMedia(item, media[0]);
    setStep(0);
    if (!viewer.open) {
      viewer.showModal();
      document.body.classList.add('viewer-open');
      $('#close-viewer').focus();
    }
    viewer.scrollTop = 0;
  }

  function navigate(offset) {
    const index = filtered.findIndex((entry) => entry.id === current?.id);
    const next = filtered[index + offset];
    if (next) openFeature(next);
  }
  $('#previous-step').addEventListener('click', () => setStep(stepIndex - 1));
  $('#next-step').addEventListener('click', () => setStep(stepIndex + 1));
  $('#previous-feature').addEventListener('click', () => navigate(-1));
  $('#next-feature').addEventListener('click', () => navigate(1));
  function closeFeature() {
    if (history.state?.showcaseFeature) {
      history.back();
    } else {
      const url = new URL(location.href);
      url.searchParams.delete('feature');
      history.replaceState(history.state, '', url);
      viewer.close();
    }
  }
  $('#close-viewer').addEventListener('click', closeFeature);
  viewer.addEventListener('cancel', (event) => { event.preventDefault(); closeFeature(); });
  viewer.addEventListener('click', (event) => {
    if (event.target !== viewer) return;
    const rect = viewer.getBoundingClientRect();
    if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) closeFeature();
  });
  viewer.addEventListener('close', () => {
    $('#viewer-media').querySelector('video')?.pause();
    $('#viewer-media').replaceChildren();
    document.body.classList.remove('viewer-open');
    if (returnFocus?.isConnected) returnFocus.focus({ preventScroll: true });
  });
  viewer.addEventListener('keydown', (event) => {
    if (event.target.closest('video, input, button, summary')) return;
    if (event.key === 'ArrowLeft') { event.preventDefault(); navigate(-1); }
    if (event.key === 'ArrowRight') { event.preventDefault(); navigate(1); }
  });
  window.addEventListener('popstate', () => {
    if (!catalog) return;
    const id = new URL(location.href).searchParams.get('feature');
    const item = catalog.items.find((entry) => entry.id === id);
    if (item) {
      if (!filtered.some((entry) => entry.id === id)) {
        chapter = 'all';
        $('#search').value = '';
        $('#media-filter').value = 'all';
        renderChapters();
        renderGallery();
      }
      openFeature(item, null, false);
    } else if (viewer.open) viewer.close();
  });

  function renderChecklist() {
    const items = catalog.items.filter((item) => item.id !== 'original-sos');
    $('#capture-total').textContent = `${items.length} features`;
    const list = $('#capture-items');
    items.sort((a, b) => Number(hasMedia(a)) - Number(hasMedia(b))).forEach((item) => {
      const row = element('article', 'capture-item');
      row.append(element('h3', '', `${item.title} · ${hasMedia(item) ? 'Refresh / complete' : 'New capture'}`), element('p', '', item.capture), element('code', '', item.captureFile));
      list.append(row);
    });
  }

  function toast(message) {
    clearTimeout(toastTimer);
    $('#toast').textContent = message;
    $('#toast').hidden = false;
    toastTimer = setTimeout(() => { $('#toast').hidden = true; }, 5000);
  }
  async function copyLink(url, message) {
    try {
      await navigator.clipboard.writeText(url);
      toast(message);
    } catch {
      toast(`Copy this link from your address bar: ${url}`);
    }
  }
  $('#copy-link').addEventListener('click', () => copyLink(`${location.origin}${base}`, 'Showcase link copied. Share with your internal audience.'));
  $('#copy-feature-link').addEventListener('click', () => current && copyLink(featureUrl(current.id).href, 'Walkthrough link copied.'));
  $('#start-tour').addEventListener('click', () => catalog && openFeature(catalog.items[0], $('#start-tour')));
  $('#search').addEventListener('input', () => catalog && renderGallery());
  $('#media-filter').addEventListener('change', () => catalog && renderGallery());
  $('#reset-filters').addEventListener('click', () => {
    chapter = 'all';
    $('#search').value = '';
    $('#media-filter').value = 'all';
    renderChapters();
    renderGallery();
    $('#search').focus();
  });

  fetch(`${base}catalog.json`, { cache: 'no-store' })
    .then((response) => {
      if (!response.ok) throw new Error('Unable to load catalog');
      return response.json();
    })
    .then((data) => {
      if (!Array.isArray(data.items) || !Array.isArray(data.chapters)) throw new Error('Invalid catalog');
      catalog = data;
      $('#feature-count').textContent = catalog.items.length;
      $('#media-count').textContent = catalog.items.filter(hasMedia).length;
      $('#missing-count').textContent = catalog.items.filter((item) => !hasMedia(item)).length;
      $('#catalog-date').textContent = new Intl.DateTimeFormat('en-GB', { day: 'numeric', month: 'long', year: 'numeric' }).format(new Date(`${catalog.updated}T00:00:00`));
      $('#start-tour').disabled = false;
      renderChapters();
      renderGallery();
      renderChecklist();
      const initialId = new URL(location.href).searchParams.get('feature');
      const initial = catalog.items.find((item) => item.id === initialId);
      if (initial) openFeature(initial, null, false);
    })
    .catch(() => {
      $('#load-error').hidden = false;
      $('#results-summary').textContent = 'Feature library unavailable';
    });
})();
