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
  const evolutionRail = document.querySelector("[data-evolution-rail]");
  const evolutionCards = [...document.querySelectorAll("[data-evolution-card]")];
  const evolutionPrevious = document.querySelector("[data-evolution-previous]");
  const evolutionNext = document.querySelector("[data-evolution-next]");
  const evolutionCurrent = document.querySelector("[data-evolution-current]");
  const evolutionTotal = document.querySelector("[data-evolution-total]");
  const evolutionProgress = document.querySelector("[data-evolution-progress]");
  const milestoneDialog = document.querySelector("[data-milestone-dialog]");
  const milestonePanel = milestoneDialog?.querySelector(".milestone-dialog-panel");
  const milestoneTriggers = [...document.querySelectorAll("[data-milestone-open]")];
  const milestoneCloseButtons = [...document.querySelectorAll("[data-milestone-close]")];
  const milestonePrevious = document.querySelector("[data-milestone-previous]");
  const milestoneNext = document.querySelector("[data-milestone-next]");
  const milestoneVideo = document.querySelector("[data-milestone-motion-video]");
  const milestoneVideoToggle = document.querySelector("[data-milestone-video-toggle]");
  let activeIndex = 0;
  let rotationTimer = null;
  let carouselTimer = null;
  let carouselResumeTimer = null;
  let carouselInView = false;
  let carouselHovered = false;
  let carouselFocused = false;
  let mouseDrag = null;
  let evolutionDrag = null;
  let suppressMilestoneOpen = false;
  let activeMilestoneIndex = 0;
  let lastMilestoneTrigger = null;
  let milestoneCloseTimer = null;

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

  const milestoneStories = [
    {
      id: "foundation",
      date: "28 May 2026",
      era: "Foundation",
      title: "The first circle",
      lead: "The first version established HikerCircle as a calm, approachable hiking companion, with the beginnings of an emergency experience people could understand quickly.",
      features: [
        ["Nature-first from day one", "A clear green identity and familiar controls made the experience feel at home outdoors."],
        ["Easy to return", "Straightforward account access helped hikers get back to their plans without starting over."],
        ["Safety at the centre", "SOS and trusted emergency contacts became part of the product's foundation, not an afterthought."],
      ],
      shot: ["The original home and SOS experience", "Show the earliest home screen beside the first emergency contact or SOS view."],
      motion: ["A first walk through HikerCircle", "Sign in, arrive at home, then open the first safety centre."],
      media: {
        heading: "The first safety experience.",
        description: "",
        screenshot: {
          src: "/site-assets/evolution/01-foundation-first-sos-iphone.png",
          alt: "The original HikerCircle SOS interface from 28 May 2026, shown in an iPhone portrait layout",
          badge: "Original interface · 28 May 2026",
          title: "Safety was part of the idea from day one.",
          caption: "The early SOS centre already brought manual and duress alerts, emergency context, queued delivery, and trusted contacts into one calm experience.",
        },
      },
    },
    {
      id: "companion",
      date: "11 June 2026",
      era: "Product shape",
      title: "A hiking companion emerges",
      lead: "HikerCircle expanded from a simple safety idea into an experience that could help people discover, prepare for, and share a day on the trail.",
      features: [
        ["Find the right trail", "Trail discovery and route previews gave hikers a clearer sense of where they were heading."],
        ["Prepare with confidence", "Reminders, first-aid guidance, and hazard reports put practical preparation close at hand."],
        ["Bring a circle together", "Teams, profiles, and sharing made the experience useful beyond a solo hike."],
      ],
      shot: ["Trail discovery meets community", "Pair a route preview with an early Circle or public profile screen."],
      motion: ["From idea to hiking plan", "Move from home to a trail, preview its route, then invite or view a teammate."],
      media: {
        heading: "A companion takes shape.",
        description: "",
        motion: {
          src: "/site-assets/evolution/02-companion-walkthrough-iphone.mp4?v=20260903-real-device-media",
          poster: "/site-assets/evolution/02-companion-walkthrough-poster-iphone.png?v=20260903-real-device-media",
          badge: "Product story · 11 June 2026",
          title: "From finding a trail to finding your circle.",
          caption: "The finished experience moves from a calm home view to a real trail preview, then back to the circle around the hike.",
        },
      },
    },
    {
      id: "active-safety",
      date: "14 June 2026",
      era: "Active safety",
      title: "Safety learns to listen",
      lead: "Safety began travelling with the hiker throughout an active session, offering timely warnings and at-a-glance progress even when the app was not open.",
      features: [
        ["Respond before escalating", "Fall and stillness awareness could start a clear countdown, giving the hiker time to confirm they were okay."],
        ["Visible from the home and lock screen", "Home-screen SOS widgets, app shortcuts, and Live Activities kept key actions and hike status within reach."],
        ["A hike that stays visible", "Route recording, elapsed time, and active progress created a clearer picture of the journey."],
      ],
      shot: ["Widgets and Live Activities", "Show the HikerCircle home-screen SOS widget beside an active hike on the lock screen."],
      motion: ["An active safety response", "Trigger a safety warning, cancel it safely, then reveal the ongoing hike status outside the app."],
      media: {
        heading: "Safety moves beyond the open app.",
        description: "",
        screenshot: {
          src: "/site-assets/evolution/03-active-safety-surfaces-iphone.png",
          alt: "HikerCircle home-screen safety widget and active hike Live Activity in an iPhone presentation",
          badge: "At-a-glance safety · 14 June 2026",
          title: "Important actions stay within reach.",
          caption: "The SOS widget and active-hike Live Activity kept safety controls and hike progress visible from the iPhone home and lock screens.",
        },
        motion: {
          src: "/site-assets/evolution/03-active-safety-response-iphone.mp4?v=20260903-real-device-media",
          poster: "/site-assets/evolution/03-active-safety-response-poster-iphone.png?v=20260903-real-device-media",
          badge: "Active response · 14 June 2026",
          title: "Safety begins before the trail.",
          caption: "Starting on the finished home screen, the small SOS widget expands into full SOS Actions; tapping Duress opens the safety centre and sends the silent alert.",
        },
      },
    },
    {
      id: "coordination",
      date: "18 June 2026",
      era: "Coordination",
      title: "Hikes become truly shared",
      lead: "A team could now move through one coordinated journey—from gathering everyone before departure to seeing where the group was on the trail.",
      features: [
        ["Start together", "Invitations, readiness checks, and a shared countdown helped every teammate leave at the same moment."],
        ["Stay aware together", "Live teammate positions and team tools made it easier to understand how the group was moving."],
        ["Plan around the outdoors", "Weather, scheduled outings, nearby hikes, and useful route maps made preparation more complete."],
      ],
      shot: ["A team ready to launch", "Feature the team assembly and launch countdown alongside a live group map."],
      motion: ["Invite, ready, hike", "Show a teammate joining, both hikers becoming ready, and the shared hike beginning."],
      media: {
        heading: "A hike becomes a shared promise.",
        description: "",
        screenshot: {
          src: "/site-assets/evolution/04-coordination-team-launch-iphone.jpeg",
          alt: "HikerCircle team hike launch screen showing two hikers ready to start together on an iPhone",
          badge: "Team coordination · 18 June 2026",
          title: "Everyone starts on the same page.",
          caption: "Readiness checks, a shared countdown, and a clear team view turned a plan into a coordinated departure.",
        },
        motion: {
          src: "/site-assets/evolution/04-coordination-team-flow-iphone.mp4?v=20260903-real-device-media",
          poster: "/site-assets/evolution/04-coordination-team-flow-poster-iphone.jpeg?v=20260903-real-device-media",
          badge: "Shared journey · 18 June 2026",
          title: "From getting ready to moving together.",
          caption: "From choosing a team hike to checking the real route and starting together, the flow keeps the trail, safety settings, and group view in one place.",
        },
      },
    },
    {
      id: "history-community",
      date: "24 June 2026",
      era: "Memory and community",
      title: "Every hike gains a history",
      lead: "Hikes became continuous experiences that could survive interruptions, preserve useful details, and give teams a richer place to communicate.",
      features: [
        ["Pick up where you left off", "Routes, pins, check-ins, weather, and team details could return after an interruption."],
        ["A conversation around every hike", "Direct and group chats, shared photos, and notifications kept planning and memories together."],
        ["Celebrate and look out for one another", "Achievements and separation alerts added encouragement as well as another layer of team awareness."],
      ],
      shot: ["The hike continues", "Show a restored active hike beside its conversation or shared media."],
      motion: ["Pause, return, reconnect", "Leave an active session, return to it, then open the team conversation and a saved achievement."],
    },
    {
      id: "physical-lifeline",
      date: "14 July 2026",
      era: "Beyond the phone",
      title: "A physical lifeline joins the circle",
      lead: "HikerCircle moved beyond the touchscreen with support for a small paired SOS button that could stay close even when the phone was packed away.",
      features: [
        ["Help within physical reach", "A paired button offered a direct emergency action without first navigating the phone."],
        ["Designed for deliberate activation", "A secure activation flow reduced accidental requests while keeping the action understandable."],
        ["Useful context for nearby help", "The phone could add location information when relaying the emergency request."],
      ],
      shot: ["Phone and SOS button together", "Place the paired-device screen beside a clear product photo of the physical button."],
      motion: ["Pair once, keep it ready", "Demonstrate pairing, the ready state, and a safely cancelled test activation."],
    },
    {
      id: "reliability",
      date: "21 August 2026",
      era: "Reliability",
      title: "Safety becomes more resilient",
      lead: "The safety experience was strengthened for the imperfect conditions hikers actually meet: weak coverage, a phone in the pocket, or a plan that changes before departure.",
      features: [
        ["Ready beyond the open app", "Important hike and safety actions could continue supporting the user while attention was elsewhere."],
        ["Clear delivery status", "Alerts could wait, retry, and explain their state instead of simply disappearing when coverage faded."],
        ["A better departure routine", "Readiness checks and flexible reminders helped hikers leave with their people, gear, and timing in order."],
      ],
      shot: ["Confidence in uncertain coverage", "Show a queued alert state alongside the complete pre-hike readiness summary."],
      motion: ["From offline to delivered", "Begin with weak coverage, show an alert waiting, then show it completing when connection returns."],
    },
    {
      id: "reflection",
      date: "28 August 2026",
      era: "Reflection",
      title: "The trail keeps its story",
      lead: "A completed hike became more than a line on a map: it could be reviewed, understood, shared, and used to make the next outing better.",
      features: [
        ["Trail knowledge people can trust", "Ratings and shared experiences helped future hikers understand a route through the people who completed it."],
        ["See how the day unfolded", "Pace, checkpoints, route maps, and safety moments turned activity into useful insight."],
        ["Relive the group journey", "Team replay made it possible to revisit how everyone moved through the route together."],
      ],
      shot: ["A complete hike story", "Combine the finished route, pace summary, and trail rating into one editorial sequence."],
      motion: ["Replay the trail", "Scrub through a team replay, pause at a checkpoint, then open the hike summary."],
    },
    {
      id: "community",
      date: "29 August 2026",
      era: "Community intelligence",
      title: "The circle grows smarter",
      lead: "Group discovery became more open while still giving organisers control over who joined and giving hikers context about the people they might meet.",
      features: [
        ["Join in the right way", "Open groups and approval-based groups let organisers choose the welcome that suited each hike."],
        ["Know the people behind the plan", "Public hiker profiles, photos, and achievements helped potential teammates make informed choices."],
        ["Explore beyond the familiar", "More regions and community activity made it easier to discover a new place or circle."],
      ],
      shot: ["Meet the hiking community", "Feature a join request, a public hiker profile, and a community photo."],
      motion: ["Discover and join a circle", "Browse a public group, review its hikers, then request to join the outing."],
    },
    {
      id: "trust",
      date: "29 August 2026",
      era: "Trust",
      title: "Sign-in reaches modern security",
      lead: "Account protection became stronger without losing clarity, giving hikers a choice of familiar ways to confirm it was really them.",
      features: [
        ["A second layer of confidence", "WhatsApp verification added protection beyond a password alone."],
        ["Choose the method that fits", "An Authenticator app or passkey offered modern alternatives for secure access."],
        ["Extra care around important changes", "Sensitive account actions asked for another confirmation before proceeding."],
      ],
      shot: ["Security choices made clear", "Show the protection overview with WhatsApp, Authenticator, and passkey options."],
      motion: ["A secure sign-in", "Complete sign-in with a second step, then review the available protection methods."],
    },
    {
      id: "today",
      date: "1 September 2026",
      era: "Today",
      title: "HikerCircle opens outward",
      lead: "The product became easier to understand from the outside while the app gained richer trail knowledge, portable first-aid learning, and more intentional safety sharing.",
      features: [
        ["A clearer public home", "The website and privacy centre explain what HikerCircle offers and how personal information is treated."],
        ["Richer trail decisions", "Verified routes, useful imagery, ratings, and difficulty feedback help hikers choose with more context."],
        ["Prepared help and optional sharing", "Offline first-aid videos and opt-in live-location links offer support when it matters, on the hiker's terms."],
      ],
      shot: ["HikerCircle today", "Use the current trail detail, first-aid guide, and live-location sharing screens as the hero set."],
      motion: ["Plan, prepare, share", "Choose a verified trail, save first-aid guidance, then activate an optional live-location link."],
    },
    {
      id: "future",
      date: "Coming soon",
      era: "The next horizon",
      title: "The circle reaches farther",
      lead: "The team is exploring how HikerCircle could extend safety beyond the phone and beyond reliable mobile coverage. These ideas are a direction under consideration, not a guaranteed release plan.",
      concept: true,
      features: [
        ["Safety from the wrist", "Smartwatch check-ins and alerts could keep essential actions close while both hands stay free."],
        ["Longer reach on remote trails", "LoRa gateways could help selected trail areas carry small safety messages over greater distances."],
        ["A circle that carries the message", "A mesh between nearby hikers could help pass check-ins or alerts when direct mobile coverage fades."],
      ],
      shot: ["A possible connected trail kit", "Reserve this space for future watch, LoRa gateway, and trail-network concept mockups."],
      motion: ["How a message could travel", "Visualise an alert moving from a watch to nearby hikers, a gateway, and finally a trusted contact."],
    },
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

  const setMilestoneText = (selector, value) => {
    const element = milestoneDialog?.querySelector(selector);
    if (element) element.textContent = value;
  };

  const renderMilestone = (index) => {
    if (!milestoneDialog || milestoneStories.length === 0) return;
    activeMilestoneIndex = Math.max(0, Math.min(milestoneStories.length - 1, index));
    const story = milestoneStories[activeMilestoneIndex];
    const number = String(activeMilestoneIndex + 1).padStart(2, "0");

    setMilestoneText("[data-milestone-count]", `Milestone ${number} of ${milestoneStories.length}`);
    setMilestoneText("[data-milestone-date]", story.date);
    setMilestoneText("[data-milestone-era]", story.era);
    setMilestoneText("[data-milestone-title]", story.title);
    setMilestoneText("[data-milestone-lead]", story.lead);
    setMilestoneText("[data-milestone-footer-number]", number);
    setMilestoneText("[data-milestone-shot-title]", story.shot[0]);
    setMilestoneText("[data-milestone-shot-brief]", story.shot[1]);
    setMilestoneText("[data-milestone-motion-title]", story.motion[0]);
    setMilestoneText("[data-milestone-motion-brief]", story.motion[1]);

    const media = story.media;
    const screenshot = media?.screenshot;
    const motion = media?.motion;
    const hasScreenshot = Boolean(screenshot?.src);
    const hasMotion = Boolean(motion?.src);
    const hasRealMedia = hasScreenshot || hasMotion;
    const mediaGrid = milestoneDialog.querySelector("[data-milestone-media-grid]");
    const shotSlot = milestoneDialog.querySelector("[data-milestone-shot-slot]");
    const shotPlaceholder = milestoneDialog.querySelector("[data-milestone-shot-placeholder]");
    const shotMedia = milestoneDialog.querySelector("[data-milestone-shot-media]");
    const shotImage = milestoneDialog.querySelector("[data-milestone-shot-image]");
    const motionSlot = milestoneDialog.querySelector("[data-milestone-motion-slot]");
    const motionPlaceholder = milestoneDialog.querySelector("[data-milestone-motion-placeholder]");
    const motionMedia = milestoneDialog.querySelector("[data-milestone-motion-media]");
    const mediaDescription = milestoneDialog.querySelector("[data-milestone-media-description]");
    setMilestoneText("[data-milestone-media-heading]", media?.heading || "Prepared for the real product story.");
    if (mediaDescription) {
      const description = media ? media.description : "These media slots can be replaced with final screenshots or clips later without changing the layout.";
      mediaDescription.textContent = description || "";
      mediaDescription.hidden = !description;
    }
    setMilestoneText("[data-milestone-media-badge]", screenshot?.badge || "");
    setMilestoneText("[data-milestone-media-caption-title]", screenshot?.title || "");
    setMilestoneText("[data-milestone-media-caption]", screenshot?.caption || "");
    setMilestoneText("[data-milestone-motion-badge]", motion?.badge || "");
    setMilestoneText("[data-milestone-motion-caption-title]", motion?.title || "");
    setMilestoneText("[data-milestone-motion-caption]", motion?.caption || "");
    mediaGrid?.classList.toggle("has-single-media", hasRealMedia && hasScreenshot !== hasMotion);
    mediaGrid?.classList.toggle("has-media-pair", hasScreenshot && hasMotion);
    shotSlot?.classList.toggle("has-media", hasScreenshot);
    if (shotPlaceholder) shotPlaceholder.hidden = hasScreenshot;
    if (shotMedia) shotMedia.hidden = !hasScreenshot;
    if (shotSlot) shotSlot.hidden = hasRealMedia && !hasScreenshot;
    motionSlot?.classList.toggle("has-media", hasMotion);
    if (motionPlaceholder) motionPlaceholder.hidden = hasMotion;
    if (motionMedia) motionMedia.hidden = !hasMotion;
    if (motionSlot) motionSlot.hidden = hasRealMedia && !hasMotion;
    if (shotImage) {
      if (hasScreenshot) {
        shotImage.src = screenshot.src;
        shotImage.alt = screenshot.alt || "";
      } else {
        shotImage.removeAttribute("src");
        shotImage.alt = "";
      }
    }
    if (milestoneVideo) {
      milestoneVideo.pause();
      if (hasMotion) {
        if (milestoneVideo.getAttribute("src") !== motion.src) {
          milestoneVideo.src = motion.src;
          milestoneVideo.load();
        }
        if (motion.poster) milestoneVideo.poster = motion.poster;
        else milestoneVideo.removeAttribute("poster");
        milestoneVideo.play().catch(() => {});
        if (milestoneVideoToggle) {
          milestoneVideoToggle.textContent = "Pause";
          milestoneVideoToggle.setAttribute("aria-label", "Pause milestone recording");
        }
      } else {
        milestoneVideo.removeAttribute("src");
        milestoneVideo.removeAttribute("poster");
        milestoneVideo.load();
      }
    }

    const featureGrid = milestoneDialog.querySelector("[data-milestone-features]");
    if (featureGrid) {
      const featureItems = story.features.map(([title, description], featureIndex) => {
        const item = document.createElement("article");
        const itemNumber = document.createElement("span");
        const itemTitle = document.createElement("h4");
        const itemDescription = document.createElement("p");
        itemNumber.textContent = String(featureIndex + 1).padStart(2, "0");
        itemTitle.textContent = title;
        itemDescription.textContent = description;
        item.append(itemNumber, itemTitle, itemDescription);
        return item;
      });
      featureGrid.replaceChildren(...featureItems);
    }

    const conceptNote = milestoneDialog.querySelector("[data-milestone-concept]");
    if (conceptNote) conceptNote.hidden = !story.concept;
    milestoneDialog.classList.toggle("is-concept", Boolean(story.concept));
    if (milestonePrevious) {
      milestonePrevious.disabled = activeMilestoneIndex === 0;
      milestonePrevious.setAttribute("aria-label", activeMilestoneIndex === 0 ? "No previous milestone" : `Show previous milestone: ${milestoneStories[activeMilestoneIndex - 1].title}`);
    }
    if (milestoneNext) {
      milestoneNext.disabled = activeMilestoneIndex === milestoneStories.length - 1;
      milestoneNext.setAttribute("aria-label", activeMilestoneIndex === milestoneStories.length - 1 ? "No next milestone" : `Show next milestone: ${milestoneStories[activeMilestoneIndex + 1].title}`);
    }
    milestonePanel?.scrollTo({ top: 0, behavior: "auto" });
  };

  const openMilestone = (id, trigger) => {
    if (!milestoneDialog) return;
    const index = milestoneStories.findIndex((story) => story.id === id);
    if (index < 0) return;
    if (milestoneCloseTimer !== null) window.clearTimeout(milestoneCloseTimer);
    lastMilestoneTrigger = trigger || lastMilestoneTrigger;
    renderMilestone(index);
    milestoneDialog.hidden = false;
    document.body.classList.add("milestone-dialog-open");
    window.requestAnimationFrame(() => {
      milestoneDialog.classList.add("is-open");
      milestoneDialog.querySelector(".milestone-dialog-close")?.focus({ preventScroll: true });
    });
  };

  const closeMilestone = () => {
    if (!milestoneDialog || milestoneDialog.hidden) return;
    milestoneVideo?.pause();
    milestoneDialog.classList.remove("is-open");
    document.body.classList.remove("milestone-dialog-open");
    const finishClose = () => {
      milestoneDialog.hidden = true;
      milestoneCloseTimer = null;
      lastMilestoneTrigger?.focus({ preventScroll: true });
    };
    if (reducedMotion) finishClose();
    else milestoneCloseTimer = window.setTimeout(finishClose, 220);
  };

  milestoneTriggers.forEach((trigger) => trigger.addEventListener("click", (event) => {
    if (suppressMilestoneOpen) {
      event.preventDefault();
      return;
    }
    openMilestone(trigger.dataset.milestoneOpen, trigger);
  }));
  milestoneCloseButtons.forEach((button) => button.addEventListener("click", closeMilestone));
  milestonePrevious?.addEventListener("click", () => renderMilestone(activeMilestoneIndex - 1));
  milestoneNext?.addEventListener("click", () => renderMilestone(activeMilestoneIndex + 1));
  milestoneVideoToggle?.addEventListener("click", () => {
    if (!milestoneVideo) return;
    if (milestoneVideo.paused) {
      milestoneVideo.play().catch(() => {});
      milestoneVideoToggle.textContent = "Pause";
      milestoneVideoToggle.setAttribute("aria-label", "Pause milestone recording");
    } else {
      milestoneVideo.pause();
      milestoneVideoToggle.textContent = "Play";
      milestoneVideoToggle.setAttribute("aria-label", "Play milestone recording");
    }
  });
  document.addEventListener("keydown", (event) => {
    if (!milestoneDialog || milestoneDialog.hidden) return;
    if (event.key === "Escape") {
      event.preventDefault();
      closeMilestone();
      return;
    }
    if (event.key !== "Tab") return;
    const focusable = [...milestoneDialog.querySelectorAll("button:not(:disabled):not([tabindex=\"-1\"]),a[href]")];
    if (focusable.length === 0) return;
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  });

  const currentEvolutionIndex = () => {
    if (!evolutionRail || evolutionCards.length === 0) return 0;
    const railCenter = evolutionRail.scrollLeft + evolutionRail.clientWidth / 2;
    return evolutionCards.reduce((nearest, card, index) => {
      const cardCenter = card.offsetLeft + card.offsetWidth / 2;
      const distance = Math.abs(cardCenter - railCenter);
      return distance < nearest.distance ? { index, distance } : nearest;
    }, { index: 0, distance: Number.POSITIVE_INFINITY }).index;
  };

  const updateEvolution = () => {
    if (!evolutionRail || evolutionCards.length === 0) return;
    const index = currentEvolutionIndex();
    evolutionCards.forEach((card, cardIndex) => {
      const current = cardIndex === index;
      card.classList.toggle("is-current", current);
      if (current) card.setAttribute("aria-current", "step"); else card.removeAttribute("aria-current");
    });
    if (evolutionCurrent) evolutionCurrent.textContent = String(index + 1).padStart(2, "0");
    if (evolutionTotal) evolutionTotal.textContent = String(evolutionCards.length).padStart(2, "0");
    if (evolutionPrevious) evolutionPrevious.disabled = index === 0;
    if (evolutionNext) evolutionNext.disabled = index === evolutionCards.length - 1;
    if (evolutionProgress) {
      const maximum = Math.max(1, evolutionRail.scrollWidth - evolutionRail.clientWidth);
      evolutionProgress.style.transform = `scaleX(${Math.min(1, evolutionRail.scrollLeft / maximum)})`;
    }
  };

  const moveEvolution = (direction) => {
    if (!evolutionRail || evolutionCards.length === 0) return;
    const current = currentEvolutionIndex();
    const next = Math.max(0, Math.min(evolutionCards.length - 1, current + direction));
    evolutionRail.scrollTo({
      left: evolutionCards[next].offsetLeft - (evolutionRail.clientWidth - evolutionCards[next].offsetWidth) / 2,
      behavior: reducedMotion ? "auto" : "smooth",
    });
  };

  const finishEvolutionDrag = (event) => {
    if (!evolutionRail || !evolutionDrag) return;
    if (evolutionRail.hasPointerCapture(event.pointerId)) evolutionRail.releasePointerCapture(event.pointerId);
    evolutionRail.classList.remove("is-dragging");
    const moved = evolutionDrag.moved;
    evolutionDrag = null;
    if (!moved) return;
    suppressMilestoneOpen = true;
    window.setTimeout(() => { suppressMilestoneOpen = false; }, 180);
    const nearest = evolutionCards[currentEvolutionIndex()];
    if (nearest) {
      evolutionRail.scrollTo({
        left: nearest.offsetLeft - (evolutionRail.clientWidth - nearest.offsetWidth) / 2,
        behavior: reducedMotion ? "auto" : "smooth",
      });
    }
  };

  evolutionPrevious?.addEventListener("click", () => moveEvolution(-1));
  evolutionNext?.addEventListener("click", () => moveEvolution(1));
  evolutionRail?.addEventListener("keydown", (event) => {
    if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
    event.preventDefault();
    moveEvolution(event.key === "ArrowLeft" ? -1 : 1);
  });
  evolutionRail?.addEventListener("pointerdown", (event) => {
    if (event.pointerType !== "mouse" || event.button !== 0) return;
    evolutionDrag = { pointerId: event.pointerId, startX: event.clientX, startScrollLeft: evolutionRail.scrollLeft, moved: false };
  });
  evolutionRail?.addEventListener("pointermove", (event) => {
    if (!evolutionDrag || event.pointerId !== evolutionDrag.pointerId) return;
    const movement = event.clientX - evolutionDrag.startX;
    if (Math.abs(movement) <= 3) return;
    if (!evolutionDrag.moved) {
      evolutionDrag.moved = true;
      evolutionRail.setPointerCapture(event.pointerId);
      evolutionRail.classList.add("is-dragging");
    }
    event.preventDefault();
    evolutionRail.scrollLeft = evolutionDrag.startScrollLeft - movement;
  });
  evolutionRail?.addEventListener("pointerup", finishEvolutionDrag);
  evolutionRail?.addEventListener("pointercancel", finishEvolutionDrag);
  evolutionRail?.addEventListener("pointerleave", (event) => {
    if (evolutionDrag) finishEvolutionDrag(event);
  });
  evolutionRail?.addEventListener("scroll", updateEvolution, { passive: true });
  window.addEventListener("resize", updateEvolution, { passive: true });

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
  updateEvolution();
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
