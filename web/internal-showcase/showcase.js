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
  const presentationCopy = {
    'login-security': { title: 'Protect your account', copy: 'Review extra ways to secure sign-in.' },
    'trail-discovery': { title: 'Find a trail', copy: 'Browse routes and find one that fits the day.' },
    'trail-detail': { title: 'Know the route', copy: 'See the trail, its distance and what lies ahead.' },
    'route-preview': { title: 'Preview the path', copy: 'See the route and its checkpoints before departure.' },
    'trail-forecast': { title: 'Choose the right moment', copy: 'Compare weather before setting out.' },
    'weather-map': { title: 'Weather across the area', copy: 'See rain, wind and temperature over the map.' },
    'create-hike': { title: 'Plan your way', copy: 'Start a solo hike or bring a team together.' },
    'hike-safety-settings': { title: 'Set up safety', copy: 'Choose the safety options for this hike.' },
    'required-gear': { title: 'Pack with confidence', copy: 'Check the essentials for the route, one at a time.' },
    'team-launch': { title: 'Leave together', copy: 'See when everyone is ready to start.' },
    'active-tracking': { title: 'Stay on course', copy: 'Follow the route and keep the team in view.' },
    'active-weather-sharing': { title: 'Weather & live sharing', copy: 'Check conditions and choose when to share your position.' },
    'sos-center': { title: 'Safety close at hand', copy: 'Find emergency options when they matter.' },
    'sos-queue-notes': { title: 'Understand alert status', copy: 'See what happened after an alert was started.' },
    'physical-button': { title: 'Another way to signal', copy: 'Pair a supported physical SOS button.' },
    'button-test-logs': { title: 'Check your button', copy: 'Test it safely and review its event history.' },
    'native-widgets': { title: 'Updates beyond the app', copy: 'See hike information from the phone’s home screen.' },
    'find-hikers': { title: 'Meet your circle', copy: 'Discover other hikers and their public profiles.' },
    'hike-history': { title: 'Look back on the trail', copy: 'Revisit completed hikes and the memories they hold.' },
    'achievements': { title: 'See your progress', copy: 'Follow milestones and keep exploring.' },
    'admin-diagnostics': { title: 'Support & diagnostics', copy: 'Investigate feedback and button issues.' },
  };
  // Only suppress media that describes a different screen. Partial or staged references stay visible with a brief.
  const mediaReview = {
    'route-preview': { imagePath: '/site-assets/screens/trail-detail.jpeg', suppress: true, label: 'Replace mismatched screenshot' },
    'first-aid-gear': { imagePath: '/site-assets/screens/first-aid.jpeg', label: 'Add the gear checklist' },
    'finish-rating': { imagePath: '/site-assets/screens/route-rating.jpeg', label: 'Add the completion summary' },
    'duress-demo': { imagePath: '/site-assets/evolution/03-safety-device-20260907.jpg', label: 'Replace staged demonstration' },
    'native-widgets': { imagePath: '/site-assets/evolution/03-active-safety-surfaces-iphone.png', label: 'Replace staged demonstration' },
  };

  let slides = [];
  let active = 0;
  let activeChapter = -1;
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

  function chapterSlides(index) { return slides.filter((slide) => slide.chapter === index); }
  function reviewFor(slide) {
    const review = mediaReview[slide.item.id];
    return review?.imagePath === slide.item.image ? review : null;
  }
  function usableImage(slide) { return reviewFor(slide)?.suppress ? '' : slide.item.image || ''; }
  function usableVideo(slide) { return slide.item.video || ''; }

  function renderChapterNav() {
    $('#chapter-nav').replaceChildren(...chapterSpecs.map((chapter, index) => {
      const button = makeButton(chapter.label, 'chapter-button', () => {
        const first = slides.findIndex((slide) => slide.chapter === index);
        if (first >= 0) select(first);
      });
      button.setAttribute('aria-label', `${chapter.label}, ${chapterSlides(index).length} features`);
      return button;
    }));
  }

  function renderFeatureNav(chapterIndex) {
    const nav = $('#feature-nav');
    nav.replaceChildren(...slides.map((slide, index) => ({ slide, index }))
      .filter(({ slide }) => slide.chapter === chapterIndex)
      .map(({ slide, index }) => makeButton(slide.title, 'feature-button', () => select(index))));
  }

  function stopVideo() {
    video.pause();
    video.removeAttribute('src');
    video.load();
    video.hidden = true;
  }

  function captureFiles(item) {
    const still = item.captureFile || `${item.id}.png`;
    const recording = /\brecord\b/i.test(item.capture || '') ? still.replace(/\.(png|jpe?g)$/i, '.mp4') : '';
    return recording ? `${still}  ·  ${recording}` : still;
  }

  function select(index, syncUrl = true) {
    if (index < 0 || index >= slides.length) return;
    active = index;
    const slide = slides[index];
    const item = slide.item;
    const imageSrc = usableImage(slide);
    const videoSrc = usableVideo(slide);
    const review = reviewFor(slide);
    const captureNeeded = !imageSrc && !videoSrc;
    const staged = /staged/i.test(item.notes || '');
    const needsBrief = captureNeeded || item.source === 'preview' || staged || Boolean(review);
    stopVideo();
    $('#media-error').hidden = true;
    $('#media-request').hidden = !captureNeeded;
    $('#request-title').textContent = review?.suppress ? 'A route preview capture is needed' : 'A capture is needed for this feature';
    $('#request-file').textContent = captureFiles(item);
    imageButton.hidden = !imageSrc;
    image.alt = `${slide.title} in HikerCircle`;
    if (imageSrc) image.src = imageSrc;
    else image.removeAttribute('src');
    $('#play-recording').hidden = !videoSrc;
    $('#stage-chapter').textContent = chapterSpecs[slide.chapter].label;
    const inChapter = chapterSlides(slide.chapter);
    $('#stage-count').textContent = `${String(inChapter.indexOf(slide) + 1).padStart(2, '0')} / ${String(inChapter.length).padStart(2, '0')}`;
    $('#stage-title').textContent = slide.title;
    $('#stage-description').textContent = slide.copy;
    $('#stage-source').textContent = captureNeeded ? 'Capture needed' : item.source === 'preview' ? 'Interface preview' : staged ? 'Staged / earlier capture' : 'Earlier app capture';
    const brief = $('#media-brief');
    $('#media-brief-label').textContent = review?.label || (captureNeeded ? 'What to capture' : item.source === 'preview' ? 'Replace this preview' : 'Capture / refresh instructions');
    $('#media-brief-text').textContent = item.capture || 'Capture this feature with a controlled demo account.';
    $('#media-brief-files').textContent = captureFiles(item);
    brief.open = needsBrief;
    $('#previous').disabled = index === 0;
    $('#next').disabled = index === slides.length - 1;
    $('#chapter-nav').querySelectorAll('button').forEach((button, chapterIndex) =>
      button.setAttribute('aria-pressed', String(slide.chapter === chapterIndex)));
    if (activeChapter !== slide.chapter) {
      renderFeatureNav(slide.chapter);
      activeChapter = slide.chapter;
    }
    $('#feature-nav').querySelectorAll('button').forEach((button, featureIndex) =>
      button.setAttribute('aria-current', inChapter[featureIndex] === slide ? 'true' : 'false'));
    const featureNav = $('#feature-nav');
    const selectedButton = featureNav.querySelector('[aria-current="true"]');
    if (selectedButton) {
      const delta = selectedButton.getBoundingClientRect().left - featureNav.getBoundingClientRect().left
        - (featureNav.clientWidth - selectedButton.clientWidth) / 2;
      featureNav.scrollBy({ left: delta, behavior: 'smooth' });
    }
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
    if (!usableImage(slides[active])) return;
    imageButton.hidden = true;
    $('#media-error').hidden = false;
  });
  video.addEventListener('error', () => {
    if (video.hidden) return;
    stopVideo();
    imageButton.hidden = !usableImage(slides[active]);
    $('#media-error').hidden = false;
  });
  $('#play-recording').addEventListener('click', async () => {
    const slide = slides[active];
    const src = slide && usableVideo(slide);
    if (!src) return;
    video.poster = usableImage(slide);
    video.src = src;
    imageButton.hidden = true;
    video.hidden = false;
    $('#play-recording').hidden = true;
    try { await video.play(); } catch { /* Browser controls remain available. */ }
  });

  const viewer = $('#image-viewer');
  imageButton.addEventListener('click', () => {
    const slide = slides[active];
    if (!slide || !usableImage(slide)) return;
    $('#full-image').src = usableImage(slide);
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
  $('#stage').addEventListener('touchstart', (event) => {
    if (!video.hidden) return;
    const touch = event.changedTouches[0];
    touchStart = { x: touch.clientX, y: touch.clientY };
  }, { passive: true });
  $('#stage').addEventListener('touchend', (event) => {
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
      slides = chapterSpecs.flatMap((chapter, chapterIndex) => {
        const items = chapter.only
          ? chapter.only.map((id) => catalog.items.find((item) => item.id === id)).filter(Boolean)
          : [...catalog.items.filter((item) => item.chapter === chapter.id),
              ...(chapter.extras || []).map((id) => catalog.items.find((item) => item.id === id)).filter(Boolean)];
        return items.map((item) => ({ item, chapter: chapterIndex,
          title: presentationCopy[item.id]?.title || item.title,
          copy: presentationCopy[item.id]?.copy || item.description }));
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
