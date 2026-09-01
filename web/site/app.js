(() => {
  "use strict";

  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const header = document.querySelector("[data-header]");
  const tabs = [...document.querySelectorAll("[data-showcase-tab]")];
  const scenes = [...document.querySelectorAll("[data-showcase-scene]")];
  const stage = document.querySelector("[data-showcase-stage]");
  const statsRegion = document.querySelector("[data-community-stats]");
  const statsStatus = document.querySelector("[data-stats-status]");
  const carousel = document.querySelector("[data-screen-carousel]");
  const carouselSlides = [...document.querySelectorAll("[data-carousel-slide]")];
  const carouselPrevious = document.querySelector("[data-carousel-previous]");
  const carouselNext = document.querySelector("[data-carousel-next]");
  const carouselProgress = document.querySelector("[data-carousel-progress]");
  const galleryBlock = carousel?.closest(".gallery-block");
  let activeIndex = 0;
  let rotationTimer = null;
  let carouselTimer = null;
  let carouselResumeTimer = null;
  let carouselInView = false;
  let carouselHovered = false;
  let carouselFocused = false;
  let mouseDrag = null;

  const integerFormatter = new Intl.NumberFormat("en-MY", { maximumFractionDigits: 0 });
  const distanceFormatter = new Intl.NumberFormat("en-MY", { maximumFractionDigits: 1 });
  const statKeys = [
    "registeredHikers",
    "totalDistanceKm",
    "completedHikes",
    "soloHikes",
    "groupHikes",
    "safetyCheckIns",
  ];

  const loadCommunityStats = async () => {
    if (!statsRegion) return;
    try {
      const response = await fetch("/api/public-stats", { headers: { Accept: "application/json" } });
      if (!response.ok) throw new Error(`Stats request failed with ${response.status}`);
      const stats = await response.json();
      if (!statKeys.every((key) => Number.isFinite(stats[key]) && stats[key] >= 0)) {
        throw new Error("Stats response was invalid");
      }

      statKeys.forEach((key) => {
        const formatter = key === "totalDistanceKm" ? distanceFormatter : integerFormatter;
        document.querySelectorAll(`[data-stat="${key}"]`).forEach((node) => {
          node.textContent = formatter.format(stats[key]);
        });
      });
      if (statsStatus) {
        statsStatus.textContent = "Distance includes each hiker’s recorded session in a group hike. Only aggregate totals are shown.";
      }
      statsRegion.classList.add("is-loaded");
    } catch (_) {
      if (statsStatus) statsStatus.textContent = "Community totals are temporarily unavailable. Please check again shortly.";
    } finally {
      statsRegion.removeAttribute("aria-busy");
    }
  };

  const currentCarouselIndex = () => {
    if (!carousel || carouselSlides.length === 0) return 0;
    return carouselSlides.reduce((nearest, slide, index) => {
      const distance = Math.abs(slide.offsetLeft - carousel.scrollLeft);
      return distance < nearest.distance ? { index, distance } : nearest;
    }, { index: 0, distance: Number.POSITIVE_INFINITY }).index;
  };

  const updateCarouselProgress = () => {
    if (!carousel || !carouselProgress) return;
    const maximum = Math.max(1, carousel.scrollWidth - carousel.clientWidth);
    carouselProgress.style.transform = `scaleX(${Math.min(1, carousel.scrollLeft / maximum)})`;
  };

  const moveCarousel = (direction) => {
    if (!carousel || carouselSlides.length === 0) return;
    const current = currentCarouselIndex();
    const next = (current + direction + carouselSlides.length) % carouselSlides.length;
    carousel.scrollTo({
      left: carouselSlides[next].offsetLeft,
      behavior: reducedMotion ? "auto" : "smooth",
    });
  };

  const stopCarousel = () => {
    if (carouselTimer !== null) window.clearInterval(carouselTimer);
    if (carouselResumeTimer !== null) window.clearTimeout(carouselResumeTimer);
    carouselTimer = null;
    carouselResumeTimer = null;
  };

  const startCarousel = () => {
    stopCarousel();
    if (
      reducedMotion
      || !carouselInView
      || carouselHovered
      || carouselFocused
      || mouseDrag
      || document.hidden
      || carouselSlides.length < 2
    ) return;
    carouselTimer = window.setInterval(() => moveCarousel(1), 3600);
  };

  const resumeCarouselSoon = () => {
    stopCarousel();
    if (reducedMotion) return;
    carouselResumeTimer = window.setTimeout(startCarousel, 2600);
  };

  const finishMouseDrag = (event) => {
    if (!carousel || !mouseDrag) return;
    if (carousel.hasPointerCapture(event.pointerId)) carousel.releasePointerCapture(event.pointerId);
    carousel.classList.remove("is-dragging");
    mouseDrag = null;
    const nearest = carouselSlides[currentCarouselIndex()];
    if (nearest) carousel.scrollTo({ left: nearest.offsetLeft, behavior: reducedMotion ? "auto" : "smooth" });
    resumeCarouselSoon();
  };

  carouselPrevious?.addEventListener("click", () => {
    stopCarousel();
    moveCarousel(-1);
    resumeCarouselSoon();
  });
  carouselNext?.addEventListener("click", () => {
    stopCarousel();
    moveCarousel(1);
    resumeCarouselSoon();
  });
  carousel?.addEventListener("keydown", (event) => {
    if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
    event.preventDefault();
    stopCarousel();
    moveCarousel(event.key === "ArrowLeft" ? -1 : 1);
    resumeCarouselSoon();
  });
  carousel?.addEventListener("pointerdown", (event) => {
    stopCarousel();
    if (event.pointerType !== "mouse" || event.button !== 0) return;
    mouseDrag = { pointerId: event.pointerId, startX: event.clientX, startScrollLeft: carousel.scrollLeft };
    carousel.setPointerCapture(event.pointerId);
    carousel.classList.add("is-dragging");
  });
  carousel?.addEventListener("pointermove", (event) => {
    if (!mouseDrag || event.pointerId !== mouseDrag.pointerId) return;
    const movement = event.clientX - mouseDrag.startX;
    if (Math.abs(movement) > 3) event.preventDefault();
    carousel.scrollLeft = mouseDrag.startScrollLeft - movement;
  });
  carousel?.addEventListener("pointerup", finishMouseDrag);
  carousel?.addEventListener("pointercancel", finishMouseDrag);
  carousel?.addEventListener("pointerleave", (event) => {
    if (mouseDrag) finishMouseDrag(event);
  });
  carousel?.addEventListener("touchend", resumeCarouselSoon, { passive: true });
  carousel?.addEventListener("scroll", updateCarouselProgress, { passive: true });
  galleryBlock?.addEventListener("mouseenter", () => {
    carouselHovered = true;
    stopCarousel();
  });
  galleryBlock?.addEventListener("mouseleave", () => {
    carouselHovered = false;
    startCarousel();
  });
  galleryBlock?.addEventListener("focusin", () => {
    carouselFocused = true;
    stopCarousel();
  });
  galleryBlock?.addEventListener("focusout", (event) => {
    if (!galleryBlock.contains(event.relatedTarget)) {
      carouselFocused = false;
      resumeCarouselSoon();
    }
  });
  window.addEventListener("resize", updateCarouselProgress, { passive: true });

  if (carousel && "IntersectionObserver" in window) {
    const carouselObserver = new IntersectionObserver(([entry]) => {
      carouselInView = entry.isIntersecting;
      if (carouselInView) startCarousel(); else stopCarousel();
    }, { threshold: 0.2 });
    carouselObserver.observe(carousel);
  } else if (carousel) {
    carouselInView = true;
    startCarousel();
  }

  const updateHeader = () => header?.classList.toggle("is-scrolled", window.scrollY > 24);
  const showScene = (index, restart = true) => {
    activeIndex = (index + tabs.length) % tabs.length;
    tabs.forEach((tab, itemIndex) => {
      const active = itemIndex === activeIndex;
      tab.classList.toggle("is-active", active);
      tab.setAttribute("aria-selected", String(active));
    });
    scenes.forEach((scene, itemIndex) => scene.classList.toggle("is-active", itemIndex === activeIndex));
    if (restart) startRotation();
  };

  const stopRotation = () => {
    if (rotationTimer !== null) window.clearInterval(rotationTimer);
    rotationTimer = null;
  };

  const startRotation = () => {
    stopRotation();
    if (reducedMotion || tabs.length < 2 || document.hidden) return;
    rotationTimer = window.setInterval(() => showScene(activeIndex + 1, false), 5200);
  };

  tabs.forEach((tab, index) => tab.addEventListener("click", () => showScene(index)));
  stage?.addEventListener("pointerenter", stopRotation);
  stage?.addEventListener("pointerleave", startRotation);
  stage?.addEventListener("focusin", stopRotation);
  stage?.addEventListener("focusout", startRotation);
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) {
      stopRotation();
      stopCarousel();
    } else {
      startRotation();
      startCarousel();
    }
  });

  updateHeader();
  updateCarouselProgress();
  loadCommunityStats();
  startRotation();
  window.addEventListener("scroll", updateHeader, { passive: true });

  if (!("IntersectionObserver" in window)) {
    document.querySelectorAll(".reveal").forEach((item) => item.classList.add("is-visible"));
    return;
  }

  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add("is-visible");
      observer.unobserve(entry.target);
    });
  }, { threshold: 0.12 });

  document.querySelectorAll(".reveal:not(.is-visible)").forEach((item) => observer.observe(item));
})();
