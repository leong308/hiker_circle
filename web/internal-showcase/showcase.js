// Interactive internal feature showcase, screenshot gallery, and presentation navigation.
(() => {
  'use strict';

  const $ = (selector) => document.querySelector(selector);
  const base = '/internal/app-showcase/';
  const chapterSpecs = [
    { id: 'access', label: 'Join & set up' },
    { id: 'discover', label: 'Explore trails' },
    { id: 'prepare', label: 'Prepare a hike' },
    { id: 'hike', label: 'On the trail' },
    { id: 'safety', label: 'Safety', extras: ['native-widgets'] },
    { id: 'circle', label: 'Your circle' },
    { id: 'reflect', label: 'After the hike' },
    { id: 'settings', label: 'Your app' },
    { id: 'admin', label: 'Operations' },
    { id: 'archive', label: 'Archive', only: ['original-sos'] },
  ];

  let slides = [];
  let active = 0;
  let activeChapter = -1;
  let touchStart = null;
  let toastTimer;
  let mediaIndex = 0;
  const video = $('#stage-video');
  const videoFrame = $('#video-frame');
  const image = $('#stage-image');
  const imageButton = $('#open-image');
  const imageGallery = $('#image-gallery');
  const viewer = $('#image-viewer');
  const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function makeButton(label, className, onClick) {
    const button = element('button', className, label);
    button.type = 'button';
    button.addEventListener('click', onClick);
    return button;
  }

  function chapterSlides(index) { return slides.filter((slide) => slide.chapter === index); }

  function centerSelection(nav, selector) {
    const selected = nav.querySelector(selector);
    if (!selected) return;
    const delta = selected.getBoundingClientRect().left - nav.getBoundingClientRect().left
      - (nav.clientWidth - selected.clientWidth) / 2;
    nav.scrollBy({ left: delta, behavior: reducedMotion ? 'auto' : 'smooth' });
  }

  // New phone captures are wired here after review. Shared website and preview media are not used.
  function mediaFor(item) {
    if (item.source !== 'device') return [];
    const isNewCapture = (src) => typeof src === 'string' && src.startsWith(base + 'media/');
    const media = [];
    if (isNewCapture(item.image)) media.push({ kind: 'image', src: item.image, alt: item.title });
    for (const capture of item.images || []) {
      if (isNewCapture(capture.src) && !media.some((entry) => entry.src === capture.src)) {
        media.push({ kind: 'image', src: capture.src, alt: capture.alt || item.title });
      }
    }
    if (isNewCapture(item.video)) media.push({ kind: 'video', src: item.video, poster: isNewCapture(item.poster) ? item.poster : null });
    for (const capture of item.videos || []) {
      if (isNewCapture(capture.src) && !media.some((entry) => entry.src === capture.src)) {
        media.push({ kind: 'video', src: capture.src, poster: isNewCapture(capture.poster) ? capture.poster : null, alt: capture.alt || item.title });
      }
    }
    return media;
  }

  function renderChapterNav() {
    $('#chapter-nav').replaceChildren(...chapterSpecs.map((chapter, index) => {
      const button = makeButton(chapter.label, 'chapter-button', () => {
        const first = slides.findIndex((slide) => slide.chapter === index);
        if (first >= 0) select(first);
      });
      button.setAttribute('aria-label', chapter.label + ', ' + chapterSlides(index).length + ' features');
      return button;
    }));
  }

  function renderFeatureNav(chapterIndex) {
    $('#feature-nav').replaceChildren(...slides.map((slide, index) => ({ slide, index }))
      .filter(({ slide }) => slide.chapter === chapterIndex)
      .map(({ slide, index }) => makeButton(slide.item.title, 'feature-button', () => select(index))));
  }

  function renderPoints(item) {
    const list = $('#stage-points');
    const disclosures = [];
    list.replaceChildren(...item.points.map((point, index) => {
      const row = element('li');
      const details = element('details', 'feature-point');
      const summary = element('summary');
      const number = element('span', 'point-number', String(index + 1).padStart(2, '0'));
      number.setAttribute('aria-hidden', 'true');
      const icon = element('span', 'point-toggle', '+');
      icon.setAttribute('aria-hidden', 'true');
      summary.append(number, element('span', '', point.label), icon);
      details.append(summary, element('p', '', point.detail));
      disclosures.push(details);
      details.addEventListener('toggle', () => {
        if (details.open) disclosures.forEach((other) => { if (other !== details) other.open = false; });
      });
      row.append(details);
      return row;
    }));
  }

  function renderCapture(item) {
    const plan = item.capturePlan;
    const recording = plan.recording;
    const shots = plan.screenshots;
    $('#request-kind').textContent = recording ? 'SCREEN RECORDING NEEDED' : 'SCREENSHOTS NEEDED';
    $('#request-duration').textContent = recording ? recording.duration : shots.length + (shots.length === 1 ? ' screen' : ' screens');
    $('#request-title').textContent = recording ? 'Record this feature.' : 'Take ' + shots.length + (shots.length === 1 ? ' screenshot.' : ' screenshots.');
    const steps = recording ? recording.steps.map((show) => ({ show })) : shots;
    $('#capture-steps').replaceChildren(...steps.map((step, index) => {
      const row = element('li');
      const number = element('span', 'capture-step-number', String(index + 1).padStart(2, '0'));
      number.setAttribute('aria-hidden', 'true');
      const copy = element('div');
      copy.append(element('p', '', step.show));
      if (step.file) copy.append(element('code', '', step.file));
      row.append(number, copy);
      return row;
    }));
    $('#capture-setup').textContent = plan.setup || '';
    $('#capture-setup').hidden = !plan.setup;
    $('#request-file').textContent = recording ? recording.file : '';
    $('#request-file').hidden = !recording;
  }

  function stopVideo() {
    video.pause();
    video.removeAttribute('src');
    video.removeAttribute('poster');
    video.load();
    video.hidden = true;
    videoFrame.hidden = true;
  }

  function openScreenshot(src, alt) {
    $('#full-image').src = src;
    $('#full-image').alt = alt;
    viewer.showModal();
    $('#close-image').focus();
  }

  function showMedia(index) {
    const slide = slides[active];
    if (!slide) return;
    const media = mediaFor(slide.item);
    stopVideo();
    imageButton.hidden = true;
    imageGallery.hidden = true;
    imageGallery.replaceChildren();
    image.removeAttribute('src');
    $('#play-recording').hidden = true;
    $('#media-error').hidden = true;
    $('#media-request').hidden = media.length > 0;
    $('#media-switcher').hidden = media.length < 2;
    if (!media.length) return;
    if (media.length > 1 && media.every((entry) => entry.kind === 'image')) {
      $('#media-switcher').hidden = true;
      imageGallery.replaceChildren(...media.map((capture) => {
        const button = makeButton('', 'phone-frame', () => openScreenshot(capture.src, capture.alt + ' in HikerCircle'));
        button.setAttribute('aria-label', 'View ' + capture.alt + ' screenshot full size');
        const shot = element('img');
        shot.alt = capture.alt + ' in HikerCircle';
        shot.src = capture.src;
        shot.addEventListener('error', () => { $('#media-error').hidden = false; });
        button.append(shot);
        return button;
      }));
      imageGallery.hidden = false;
      return;
    }
    mediaIndex = (index + media.length) % media.length;
    const selected = media[mediaIndex];
    $('#media-count').textContent = String(mediaIndex + 1) + ' / ' + media.length;
    if (selected.kind === 'image') {
      image.src = selected.src;
      image.alt = selected.alt + ' in HikerCircle';
      imageButton.hidden = false;
    } else {
      video.src = selected.src;
      const poster = media.find((entry) => entry.kind === 'image');
      if (selected.poster || poster) video.poster = selected.poster || poster.src;
      video.setAttribute('aria-label', (selected.alt || slide.item.title) + ' screen recording');
      video.hidden = false;
      videoFrame.hidden = false;
      video.muted = true;
      const playbackSrc = video.src;
      video.play().catch(() => {
        if (video.src === playbackSrc && !video.hidden && !video.error) $('#play-recording').hidden = false;
      });
    }
  }

  function select(index, syncUrl = true) {
    if (index < 0 || index >= slides.length) return;
    active = index;
    const slide = slides[index];
    const item = slide.item;
    $('#stage-chapter').textContent = chapterSpecs[slide.chapter].label;
    const inChapter = chapterSlides(slide.chapter);
    $('#stage-count').textContent = String(inChapter.indexOf(slide) + 1).padStart(2, '0') + ' / ' + String(inChapter.length).padStart(2, '0');
    $('#stage-title').textContent = item.title;
    renderPoints(item);
    renderCapture(item);
    showMedia(0);
    $('#previous').disabled = index === 0;
    $('#next').disabled = index === slides.length - 1;
    $('#chapter-nav').querySelectorAll('button').forEach((button, chapterIndex) =>
      button.setAttribute('aria-pressed', String(slide.chapter === chapterIndex)));
    if (activeChapter !== slide.chapter) {
      renderFeatureNav(slide.chapter);
      activeChapter = slide.chapter;
      centerSelection($('#chapter-nav'), '[aria-pressed="true"]');
    }
    $('#feature-nav').querySelectorAll('button').forEach((button, featureIndex) =>
      button.setAttribute('aria-current', inChapter[featureIndex] === slide ? 'true' : 'false'));
    centerSelection($('#feature-nav'), '[aria-current="true"]');
    if (syncUrl) {
      const url = new URL(location.href);
      url.searchParams.set('feature', item.id);
      history.replaceState(history.state, '', url);
    }
  }

  function navigate(offset) { select(active + offset); }
  $('#previous').addEventListener('click', () => navigate(-1));
  $('#next').addEventListener('click', () => navigate(1));
  $('#media-previous').addEventListener('click', () => showMedia(mediaIndex - 1));
  $('#media-next').addEventListener('click', () => showMedia(mediaIndex + 1));

  image.addEventListener('error', () => {
    if (!image.getAttribute('src')) return;
    imageButton.hidden = true;
    $('#media-switcher').hidden = true;
    $('#media-request').hidden = false;
    $('#media-error').hidden = false;
  });
  video.addEventListener('error', () => {
    // A queued event from a previous source must not hide the current capture.
    if (!video.getAttribute('src') || !video.error) return;
    video.pause();
    $('#play-recording').hidden = true;
    $('#media-request').hidden = false;
    $('#media-error').hidden = false;
  });
  $('#play-recording').addEventListener('click', async () => {
    if (!video.getAttribute('src')) return;
    $('#play-recording').hidden = true;
    try { await video.play(); } catch { /* Native player controls remain available. */ }
  });

  imageButton.addEventListener('click', () => {
    if (!image.getAttribute('src')) return;
    openScreenshot(image.src, image.alt);
  });
  $('#close-image').addEventListener('click', () => viewer.close());
  viewer.addEventListener('click', (event) => { if (event.target === viewer) viewer.close(); });

  function setPresentation(enabled) {
    document.body.classList.toggle('is-presenting', enabled);
    $('#presentation-toggle').setAttribute('aria-pressed', String(enabled));
    $('#presentation-toggle').replaceChildren(document.createTextNode(enabled ? 'Exit presentation' : 'Present'), element('span', '', enabled ? '×' : '↗'));
    $('#presentation-toggle').lastElementChild.setAttribute('aria-hidden', 'true');
    if (enabled) $('#highlights').scrollIntoView({ behavior: reducedMotion ? 'auto' : 'smooth', block: 'start' });
  }
  $('#presentation-toggle').addEventListener('click', () => setPresentation(!document.body.classList.contains('is-presenting')));
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && document.body.classList.contains('is-presenting') && !viewer.open) {
      setPresentation(false);
      $('#presentation-toggle').focus();
    }
  });

  $('#stage').addEventListener('keydown', (event) => {
    if (event.target === video || viewer.open) return;
    if (event.key === 'ArrowLeft') { event.preventDefault(); navigate(-1); }
    if (event.key === 'ArrowRight') { event.preventDefault(); navigate(1); }
  });
  $('#stage').addEventListener('touchstart', (event) => {
    if (!video.hidden) return;
    const touch = event.changedTouches[0];
    touchStart = { x: touch.clientX, y: touch.clientY };
  }, { passive: true });
  $('#stage').addEventListener('touchend', (event) => {
    if (!touchStart) return;
    const touch = event.changedTouches[0];
    const dx = touch.clientX - touchStart.x;
    const dy = touch.clientY - touchStart.y;
    touchStart = null;
    if (video.hidden && Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy) * 1.4) navigate(dx < 0 ? 1 : -1);
  }, { passive: true });

  function toast(message) {
    clearTimeout(toastTimer);
    $('#toast').textContent = message;
    $('#toast').hidden = false;
    toastTimer = setTimeout(() => { $('#toast').hidden = true; }, 3500);
  }
  $('#copy-link').addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(location.href);
      toast('Showcase link copied.');
    } catch { toast('Copy the link from your address bar.'); }
  });

  fetch(base + 'catalog.json', { cache: 'no-store' })
    .then((response) => { if (!response.ok) throw new Error('Catalog unavailable'); return response.json(); })
    .then((catalog) => {
      slides = chapterSpecs.flatMap((chapter, chapterIndex) => {
        const items = chapter.only
          ? chapter.only.map((id) => catalog.items.find((item) => item.id === id)).filter(Boolean)
          : [...catalog.items.filter((item) => item.chapter === chapter.id),
              ...(chapter.extras || []).map((id) => catalog.items.find((item) => item.id === id)).filter(Boolean)];
        return items.map((item) => ({ item, chapter: chapterIndex }));
      });
      if (slides.length !== catalog.items.length || new Set(slides.map((slide) => slide.item.id)).size !== catalog.items.length) {
        throw new Error('Showcase chapter inventory does not match catalog');
      }
      renderChapterNav();
      const requested = new URL(location.href).searchParams.get('feature');
      const index = slides.findIndex((slide) => slide.item.id === requested);
      const defaultIndex = slides.findIndex((slide) => slide.item.id === 'trail-discovery');
      select(index < 0 ? defaultIndex : index, false);
    })
    .catch(() => {
      $('#stage').hidden = true;
      $('#load-error').hidden = false;
    });
})();
