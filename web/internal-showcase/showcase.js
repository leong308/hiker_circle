(() => {
  'use strict';

  const $ = (selector) => document.querySelector(selector);
  const base = '/internal/app-showcase/';
  const chapters = [
    { title: 'Explore', start: 0 },
    { title: 'Prepare', start: 3 },
    { title: 'Stay safer', start: 6 },
    { title: 'Connect & reflect', start: 10 },
  ];
  const highlights = [
    { id: 'trail-discovery', chapter: 0, title: 'Find a trail', copy: 'Browse routes and find one that fits the day.' },
    { id: 'trail-detail', chapter: 0, title: 'Know the route', copy: 'See the trail, its distance and what lies ahead.' },
    { id: 'trail-forecast', chapter: 0, title: 'Choose the right moment', copy: 'Compare weather before setting out.' },
    { id: 'create-hike', chapter: 1, title: 'Plan your way', copy: 'Start a solo hike or bring a team together.' },
    { id: 'required-gear', chapter: 1, title: 'Pack with confidence', copy: 'Check the essentials for the route, one at a time.' },
    { id: 'team-launch', chapter: 1, title: 'Leave together', copy: 'See when everyone is ready to start.' },
    { id: 'active-tracking', chapter: 2, title: 'Stay on course', copy: 'Follow the route and keep the team in view.' },
    { id: 'sos-center', chapter: 2, title: 'Safety close at hand', copy: 'Find emergency options when they matter.' },
    { id: 'physical-button', chapter: 2, title: 'Another way to signal', copy: 'Pair a supported physical SOS button.' },
    { id: 'native-widgets', chapter: 2, title: 'Updates beyond the app', copy: 'See hike information from the phone’s home screen.' },
    { id: 'find-hikers', chapter: 3, title: 'Meet your circle', copy: 'Discover other hikers and their public profiles.' },
    { id: 'hike-history', chapter: 3, title: 'Look back on the trail', copy: 'Revisit completed hikes and the memories they hold.' },
    { id: 'achievements', chapter: 3, title: 'See your progress', copy: 'Follow milestones and keep exploring.' },
  ];

  let slides = [];
  let active = 0;
  let touchStart = null;
  let toastTimer;
  const video = $('#stage-video');
  const image = $('#stage-image');
  const imageButton = $('#open-image');

  function makeButton(label, className, onClick) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = className;
    button.textContent = label;
    button.addEventListener('click', onClick);
    return button;
  }

  function renderNavigation() {
    $('#chapter-nav').replaceChildren(...chapters.map((chapter) =>
      makeButton(chapter.title, 'chapter-button', () => select(chapter.start))));
    $('#slide-dots').replaceChildren(...slides.map((slide, index) => {
      const button = makeButton('', 'slide-dot', () => select(index));
      button.setAttribute('aria-label', `Show ${slide.title}`);
      button.title = slide.title;
      return button;
    }));
  }

  function stopVideo() {
    video.pause();
    video.removeAttribute('src');
    video.load();
    video.hidden = true;
    imageButton.hidden = false;
  }

  function select(index, syncUrl = true) {
    if (index < 0 || index >= slides.length) return;
    active = index;
    const slide = slides[index];
    const item = slide.item;
    stopVideo();
    $('#media-error').textContent = item.image ? 'Media is unavailable. Try another highlight.' : 'A screen capture has not been added yet.';
    $('#media-error').hidden = Boolean(item.image);
    imageButton.hidden = !item.image;
    image.alt = `${slide.title} in HikerCircle`;
    if (item.image) image.src = item.image;
    else image.removeAttribute('src');
    $('#play-recording').hidden = !item.video;
    $('#stage-chapter').textContent = chapters[slide.chapter]?.title || 'More features';
    $('#stage-count').textContent = `${String(index + 1).padStart(2, '0')} / ${String(slides.length).padStart(2, '0')}`;
    $('#stage-title').textContent = slide.title;
    $('#stage-description').textContent = slide.copy;
    $('#stage-source').textContent = !item.image ? 'Capture pending' : item.source === 'preview' ? 'Interface preview' : item.chapter === 'archive' ? 'Staged / earlier capture' : '';
    $('#previous').disabled = index === 0;
    $('#next').disabled = index === slides.length - 1;
    $('#chapter-nav').querySelectorAll('button').forEach((button, chapterIndex) =>
      button.setAttribute('aria-pressed', String(slide.chapter === chapterIndex)));
    $('#slide-dots').querySelectorAll('button').forEach((button, dotIndex) =>
      button.setAttribute('aria-current', dotIndex === index ? 'true' : 'false'));
    if (syncUrl) {
      const url = new URL(location.href);
      url.searchParams.set('feature', item.id);
      history.replaceState(history.state, '', url);
    }
  }

  function navigate(offset) { select(active + offset); }
  $('#previous').addEventListener('click', () => navigate(-1));
  $('#next').addEventListener('click', () => navigate(1));

  image.addEventListener('error', () => {
    if (!slides[active]?.item.image) return;
    imageButton.hidden = true;
    $('#media-error').hidden = false;
  });
  video.addEventListener('error', () => {
    if (video.hidden) return;
    stopVideo();
    $('#media-error').hidden = false;
  });
  $('#play-recording').addEventListener('click', async () => {
    const item = slides[active]?.item;
    if (!item?.video) return;
    video.poster = item.image;
    video.src = item.video;
    imageButton.hidden = true;
    video.hidden = false;
    $('#play-recording').hidden = true;
    try { await video.play(); } catch { /* Browser controls remain available. */ }
  });

  const viewer = $('#image-viewer');
  imageButton.addEventListener('click', () => {
    $('#full-image').src = slides[active].item.image;
    $('#full-image').alt = image.alt;
    viewer.showModal();
    $('#close-image').focus();
  });
  $('#close-image').addEventListener('click', () => viewer.close());
  viewer.addEventListener('click', (event) => { if (event.target === viewer) viewer.close(); });

  $('#stage').addEventListener('keydown', (event) => {
    if (event.target === video || viewer.open) return;
    if (event.key === 'ArrowLeft') { event.preventDefault(); navigate(-1); }
    if (event.key === 'ArrowRight') { event.preventDefault(); navigate(1); }
  });
  $('.stage-media').addEventListener('touchstart', (event) => {
    if (!video.hidden) return;
    const touch = event.changedTouches[0];
    touchStart = { x: touch.clientX, y: touch.clientY };
  }, { passive: true });
  $('.stage-media').addEventListener('touchend', (event) => {
    if (!touchStart || !video.hidden) return;
    const touch = event.changedTouches[0];
    const dx = touch.clientX - touchStart.x;
    const dy = touch.clientY - touchStart.y;
    touchStart = null;
    if (Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy) * 1.4) navigate(dx < 0 ? 1 : -1);
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

  fetch(`${base}catalog.json`, { cache: 'no-store' })
    .then((response) => { if (!response.ok) throw new Error('Catalog unavailable'); return response.json(); })
    .then((catalog) => {
      slides = highlights.map((highlight) => {
        const item = catalog.items.find((entry) => entry.id === highlight.id);
        if (!item?.image) throw new Error(`Missing showcase media: ${highlight.id}`);
        return { ...highlight, item };
      });
      const requested = new URL(location.href).searchParams.get('feature');
      if (requested && !slides.some((slide) => slide.id === requested)) {
        const item = catalog.items.find((entry) => entry.id === requested);
        if (item) slides.push({ id: item.id, chapter: 4, title: item.title, copy: item.description, item });
      }
      renderNavigation();
      const index = slides.findIndex((slide) => slide.id === requested);
      select(index < 0 ? 0 : index, false);
    })
    .catch(() => {
      $('#stage').hidden = true;
      $('#load-error').hidden = false;
    });
})();
