// Landing-page navigation, trail preview, and accessible evolution timeline interactions.
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
      motion: ["A first walk through HikerCircle", "Sign in, show Home, then open the first SOS centre."],
      media: {
        heading: "The first safety experience.",
        description: "",
        screenshot: {
          provenance: "Historical design · May 2026",
          src: "/site-assets/evolution/01-foundation-first-sos-iphone.png",
          alt: "The original HikerCircle SOS interface from 28 May 2026, shown in an iPhone portrait layout",
          badge: "Original interface · 28 May 2026",
          title: "Safety was part of the idea from day one.",
          caption: "A preserved reference of the original SOS design. Its capture date is unrecorded; the design belongs to the May 2026 foundation milestone.",
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
        description: "Current trail discovery and route tools, captured on 16 November 2026.",
        screenshot: {
          src: "/internal/app-showcase/media/trail-detail.png",
          alt: "Current HikerCircle public Penang Hill Heritage Trail page with loaded trail photograph and route information",
          badge: "Device capture · 16 Nov 2026",
          provenance: "Device capture · 16 Nov 2026",
          title: "Get to know the trail.",
          caption: "Explore the public Penang Hill Heritage Trail and review its route information before planning a hike."
        },
        motion: {
          src: "/internal/app-showcase/media/trail-discovery.mp4",
          poster: "/internal/app-showcase/media/trail-discovery.png",
          badge: "Current UI · device demo · 16 Nov 2026",
          provenance: "Current UI · device demo · 16 Nov 2026",
          title: "Find a trail that fits.",
          caption: "Browse the current Home grid and list, then open fictional trail details in an isolated connected-device demonstration."
        }
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
          src: "/internal/app-showcase/media/sos-status.png",
          alt: "Current HikerCircle full-screen manual SOS response in an isolated device demo",
          badge: "Current UI · device demo · 16 Nov 2026",
          provenance: "Current UI · device demo · 16 Nov 2026",
          title: "A clearer safety response.",
          caption: "The current SOS response interface is shown with fictional contacts in an isolated device demo. No emergency message is sent.",
        },
        motion: {
          provenance: "Current UI · device demo · 16 Nov 2026",
          src: "/internal/app-showcase/media/active-tracking.mp4",
          poster: "/internal/app-showcase/media/active-team-hike.png",
          badge: "Current UI · device demo · 16 Nov 2026",
          title: "Keep your hike and safety tools together.",
          caption: "Zoom and recenter the current active-hike map, then open safety and sharing controls. This isolated device demonstration uses a fictional route and team.",
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
          src: "/internal/app-showcase/media/preparation-review.png",
          alt: "Current HikerCircle preparation checklist for a fictional hike in an isolated device demo",
          badge: "Current UI · device demo · 16 Nov 2026",
          provenance: "Current UI · device demo · 16 Nov 2026",
          title: "Get ready before departure.",
          caption: "Review the current preparation checklist before setting off. This connected-device demonstration uses fictional hiking data."
        },
        motion: {
          provenance: "Current UI · device demo · 16 Nov 2026",
          src: "/internal/app-showcase/media/team-tools.mp4",
          poster: "/internal/app-showcase/media/team-locations.png",
          badge: "Current UI · device demo · 16 Nov 2026",
          title: "See who is on the hike.",
          caption: "Review the current team roster and Team locations map with fictional hikers in an isolated device demo. No real pings or invitations are sent.",
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
      media: {
        heading: "Every adventure leaves something behind.",
        description: "Revisit past hikes and see how each outing adds to your progress.",
        screenshot: {
          src: "/internal/app-showcase/media/hike-history-demo.png",
          alt: "Current HikerCircle hike history with fictional saved hikes in an isolated device demo",
          badge: "Current UI · device demo · 16 Nov 2026",
          provenance: "Current UI · device demo · 16 Nov 2026",
          title: "A record to return to.",
          caption: "The current history view brings saved hikes together. This connected-device demonstration uses fictional hiking records.",
        },
        motion: {
          provenance: "Demo account · 16 Nov 2026",
          src: "/internal/app-showcase/media/achievements.mp4",
          poster: "/internal/app-showcase/media/achievements.png",
          badge: "Demo account · 16 Nov 2026",
          title: "See your progress add up.",
          caption: "Browse the current demo account’s achievements overview, earned badges and progress details.",
        },
      },
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
      media: {
        heading: "Safety within physical reach.",
        description: "A dedicated SOS button brings an emergency control closer when your phone is packed away.",
        screenshot: {
          src: "/internal/app-showcase/media/physical-button-setup.png",
          alt: "Current HikerCircle guided physical SOS button setup instructions in the main app",
          badge: "Current app · demo account · 16 Nov 2026",
          provenance: "Current app · demo account · 16 Nov 2026",
          title: "Prepare your physical SOS button.",
          caption: "Read the current guided setup instructions before pairing a compatible physical button. Captured in the main app with a demo account."
        },
        motion: {
          provenance: "Current UI · simulated hardware · 16 Nov 2026",
          src: "/internal/app-showcase/media/physical-button.mp4",
          poster: "/internal/app-showcase/media/physical-button-success.png",
          badge: "Current UI · simulated hardware · 16 Nov 2026",
          title: "Pair a button, step by step.",
          caption: "Simulated discovery, confirmation and success demonstrate the current pairing flow. The device recording keeps a SIMULATED HARDWARE banner visible and does not pair real hardware or send an SOS.",
        },
      },
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
      media: {
        heading: "Prepare for the unexpected.",
        description: "Set up your safety checks before heading onto the trail.",
        screenshot: {
          src: "/internal/app-showcase/media/hike-safety-settings.png",
          alt: "Current pre-hike safety settings in HikerCircle, shown in an isolated device demo",
          badge: "Current UI · device demo · 16 Nov 2026",
          provenance: "Current UI · device demo · 16 Nov 2026",
          title: "Make safety part of your preparation.",
          caption: "Review the current pre-hike safety settings using fictional hiking data in an isolated device demo.",
        },
        motion: {
          provenance: "Current UI · device demo · 16 Nov 2026",
          src: "/internal/app-showcase/media/required-gear.mp4",
          poster: "/internal/app-showcase/media/required-gear.png",
          badge: "Current UI · device demo · 16 Nov 2026",
          title: "Review what you will carry.",
          caption: "Tick required gear items and review extras and battery guidance for a fictional hike in an isolated device demonstration.",
        },
      },
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
      media: {
        heading: "Look back. Take more forward.",
        description: "Revisit the details of a completed hike and the plan that shaped your day.",
        screenshot: {
          src: "/internal/app-showcase/media/hike-analysis-demo.png",
          alt: "Current HikerCircle hike analysis with fictional saved hiking data in an isolated device demo",
          badge: "Current UI · device demo · 16 Nov 2026",
          provenance: "Current UI · device demo · 16 Nov 2026",
          title: "Look back at the details.",
          caption: "Review the current hike-analysis view using fictional saved hiking data in an isolated device demo.",
        },
        motion: {
          provenance: "Current UI · device demo · 16 Nov 2026",
          src: "/internal/app-showcase/media/hike-analysis.mp4",
          poster: "/internal/app-showcase/media/hike-analysis-demo.png",
          badge: "Current UI · device demo · 16 Nov 2026",
          title: "Revisit the details of your day.",
          caption: "Explore the current overview, analysis and safety views for a fictional saved hike in an isolated device demonstration.",
        },
      },
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
      media: {
        heading: "Find your hiking people.",
        description: "Discover fellow hikers and learn a little about them before connecting.",
        screenshot: {
          src: "/internal/app-showcase/media/find-hikers.png",
          alt: "Current HikerCircle Find Hikers view with fictional profiles in an isolated device demo",
          badge: "Current UI · device demo · 16 Nov 2026",
          provenance: "Current UI · device demo · 16 Nov 2026",
          title: "Find your hiking people.",
          caption: "The current hiker-discovery view is shown with fictional profiles in an isolated connected-device demonstration."
        },
        motion: {
          provenance: "Current UI · device demo · 16 Nov 2026",
          src: "/internal/app-showcase/media/community.mp4",
          poster: "/internal/app-showcase/media/community.png",
          badge: "Current UI · device demo · 16 Nov 2026",
          title: "Meet the people behind the stories.",
          caption: "Move from the current stories feed to Find Hikers and a fictional public profile in an isolated device demo. No real requests, posts or messages are sent.",
        },
      },
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
      motion: ["A secure sign-in", "Sign in with a second step, keeping codes and personal details hidden."],
      media: {
        heading: "Confidence starts with your account.",
        description: "Review your sign-in protection in one clear place.",
        screenshot: {
          src: "/internal/app-showcase/media/login-security.png",
          alt: "Current HikerCircle login-security overview with fictional Authenticator and passkey labels in an isolated device demo",
          badge: "Current UI · device demo · 16 Nov 2026",
          provenance: "Current UI · device demo · 16 Nov 2026",
          title: "Your security choices, together.",
          caption: "Review the current login-security layout with fictional method labels. This isolated demonstration exposes no setup secret or verification code.",
        },
      },
    },
    {
      id: "today",
      date: "1 September 2026",
      era: "Opening outward",
      title: "HikerCircle opens outward",
      lead: "The product became easier to understand from the outside while the app gained richer trail knowledge, portable first-aid learning, and more intentional safety sharing.",
      features: [
        ["A clearer public home", "The website and privacy centre explain what HikerCircle offers and how personal information is treated."],
        ["Richer trail decisions", "Verified routes, useful imagery, ratings, and difficulty feedback help hikers choose with more context."],
        ["Prepared help and optional sharing", "Offline first-aid videos and opt-in live-location links offer support when it matters, on the hiker's terms."],
      ],
      shot: ["HikerCircle today", "Use the current trail detail, first-aid guide, and live-location sharing screens as the hero set."],
      motion: ["Plan, prepare, share", "Choose a verified trail, save first-aid guidance, then activate an optional live-location link."],
      media: {
        heading: "Know more before you go.",
        description: "Current public trail details and route preview, captured on 16 November 2026.",
        screenshot: {
          src: "/internal/app-showcase/media/trail-detail.png",
          alt: "Current HikerCircle Penang Hill Heritage Trail details with trail photograph and hiking information",
          badge: "Device capture · 16 Nov 2026",
          provenance: "Device capture · 16 Nov 2026",
          title: "A clearer picture of the trail.",
          caption: "Trail photography and route information help you understand what lies ahead."
        },
        motion: {
          src: "/internal/app-showcase/media/route-preview.mp4",
          poster: "/internal/app-showcase/media/route-preview.png",
          badge: "Device capture · 16 Nov 2026",
          provenance: "Device capture · 16 Nov 2026",
          title: "Explore before you set off.",
          caption: "Review the public Pisang Falls Loop route map and its first-person preview before departure."
        }
      },
    },
    {
      id: "trail-confidence",
      date: "7 September 2026",
      era: "A richer trail companion",
      title: "Every adventure comes into focus",
      lead: "Planning grows more informed, progress feels more rewarding, and the circle becomes easier to explore—with clearer safety feedback when it matters.",
      features: [
        ["Find your weather window", "Explore seven-day forecasts, hourly charts, sunrise and daylight details, and weather guidance to choose a better time to head out."],
        ["See the route unfold", "Animated route previews and highlighted checkpoints make the order of a trail easier to follow, including loops and return journeys."],
        ["More reasons to keep exploring", "Expanded achievements recognise new trails, Malaysian states, team hikes, safe check-ins and community contributions. A swipeable level roadmap shows what comes next."],
        ["Discover places and people", "Broader Malaysian trail coverage, community-led difficulty feedback, and clearer Stories and Find Hikers views help you explore beyond the familiar."],
        ["Clearer feedback when it matters", "SOS requests remain queued until delivery is confirmed, while improved contact controls and live-location maps make safety information easier to manage."],
      ],
      shot: ["Your next adventure, in focus", "Show the expanded trail forecast and the achievement level roadmap in dark mode."],
      motion: ["Choose a day. Follow the trail.", "Browse forecast days and hourly charts, then explore the animated route and highlight a checkpoint on the map."],
      media: {
        heading: "Choose your weather window.",
        description: "Current trail-weather tools, captured on 16 November 2026.",
        screenshot: {
          src: "/internal/app-showcase/media/weather.png",
          alt: "Current HikerCircle trail forecast with selectable forecast days and hourly weather chart",
          badge: "Device capture · 16 Nov 2026",
          provenance: "Device capture · 16 Nov 2026",
          title: "See more of the day ahead.",
          caption: "Compare forecast days and review hourly conditions before setting off."
        },
        motion: {
          src: "/internal/app-showcase/media/trail-forecast.mp4",
          poster: "/internal/app-showcase/media/weather.png",
          badge: "Device capture · 16 Nov 2026",
          provenance: "Device capture · 16 Nov 2026",
          title: "Compare days and conditions.",
          caption: "Switch forecast days and review the temperature, rain and wind chart views for a public trail."
        }
      },
    },
    {
      id: "before-you-go",
      date: "19 September 2026",
      era: "A clearer way ahead",
      title: "See the trail. Know your next hike.",
      lead: "A new way to look ahead brings the route to life and puts each upcoming hike's most useful details within easy reach.",
      features: [
        ["See the route from the trail", "Follow a first-person preview with a moving view, compass, distance and estimated conditions along the way."],
        ["Move between your plans", "Swipe through upcoming hikes to see each destination, departure countdown and preparation progress."],
        ["Check what the day may bring", "Open the weather and preparation details for the hike you're viewing before you leave."],
      ],
      shot: ["Walk the route before you go", "Show a first-person trail preview moving along the map, with its route details updating."],
      motion: ["Your upcoming hikes, at a glance", "Swipe between two upcoming hikes on Home; open weather and preparation for one."],
      media: {
        heading: "Two ways to look ahead.",
        description: "Current first-person route preview and upcoming-hike preparation, captured on 16 November 2026.",
        screenshot: {
          src: "/internal/app-showcase/media/enhanced-preview.png",
          alt: "Current first-person preview of the public Pisang Falls Loop route in HikerCircle",
          badge: "Device capture · 16 Nov 2026",
          provenance: "Device capture · 16 Nov 2026",
          title: "See the route from the trail.",
          caption: "Follow the first-person view of a public trail before you decide to set off."
        },
        motion: {
          src: "/internal/app-showcase/media/upcoming-home.mp4",
          poster: "/internal/app-showcase/media/plan-home.png",
          badge: "Current UI · device demo · 16 Nov 2026",
          provenance: "Current UI · device demo · 16 Nov 2026",
          title: "Your next plans, at a glance.",
          caption: "Move between two fictional upcoming hikes, then review the selected plan’s preparation and extras. This isolated connected-device demonstration does not start a hike or use a real location."
        }
      },
    },
    {
      id: "prepared-response",
      date: "26 October 2026",
      era: "Ready for the real trail",
      title: "Prepare together. Respond with confidence.",
      lead: "Preparation, trail cautions and emergency feedback come together more clearly, helping hikers understand what to pack, what has changed and what happens after an alert.",
      features: [
        ["Pack for the route ahead", "Categorised required gear, battery guidance and a clearer final review help each hiker prepare before departure."],
        ["Take changing conditions seriously", "Classified hazard alerts link back to the affected trail, with another check before starting and a way to cancel an unsafe plan."],
        ["Follow the emergency response", "The full-screen SOS experience shows delivery progress and queued updates. Silencing the local alarm does not stop emergency-message delivery."],
        ["Keep the team in step", "Readiness and launch checks help a team start from a current, shared plan rather than an outdated countdown."],
      ],
      shot: ["Ready before the first step", "Show the current final preparation review and required-gear guidance."],
      motion: ["Review the plan before departure", "Open an upcoming hike, review required gear and trail cautions, then return without starting a real hike or sending an SOS."],
      media: {
        heading: "Prepare with a clearer picture.",
        description: "Current preparation controls, captured on a connected device using fictional hiking data on 16 November 2026.",
        screenshot: {
          src: "/internal/app-showcase/media/required-gear.png",
          alt: "Current HikerCircle required-gear guidance with fictional hiking data in an isolated device demo",
          badge: "Current UI · device demo · 16 Nov 2026",
          provenance: "Current UI · device demo · 16 Nov 2026",
          title: "Pack for the route ahead.",
          caption: "The current required-gear view groups preparation guidance for a fictional hike. This is an isolated device demonstration.",
        },
        motion: {
          src: "/internal/app-showcase/media/preparation-review.mp4",
          poster: "/internal/app-showcase/media/preparation-review.png",
          badge: "Current UI · device demo · 16 Nov 2026",
          provenance: "Current UI · device demo · 16 Nov 2026",
          title: "Review everything before you go.",
          caption: "Check all eight packed items, then review extras and battery guidance in the current preparation flow. This isolated device demo uses fictional hiking data and does not start a hike.",
        },
      },
    },
    {
      id: "privacy-control",
      date: "16 November 2026",
      era: "Your account, your choices",
      title: "More control. Clearer choices.",
      lead: "The latest account experience makes privacy choices more explicit, from reviewing information use before signing up to understanding a live-location link or closing an account.",
      features: [
        ["Review before you register", "A privacy notice explains the requested information, providers and overseas processing before a new phone number is submitted for registration."],
        ["Choose when to share", "Live-location sharing has its own activation and stop controls, with a reminder that anyone holding an active link can open it."],
        ["Understand account closure", "Two confirmations explain that closing an account removes its main account record and sign-in, while location records, hike history, uploaded files and other saved data remain."],
        ["Find the explanation when needed", "The Privacy Policy and Help Center keep account and privacy guidance within reach from the app."],
      ],
      shot: ["Your privacy choices, together", "Show the current account, privacy and live-location controls without exposing personal details or an active sharing link."],
      motion: ["Review your account choices", "Open the privacy and account controls, review the account-closure notice, then cancel without deleting the account or activating a sharing link."],
      media: {
        heading: "Clear choices at every step.",
        description: "Current privacy controls, captured on a connected device using an isolated demo on 16 November 2026.",
        screenshot: {
          src: "/internal/app-showcase/media/signup-privacy.png",
          alt: "Current HikerCircle privacy notice before registration, shown in an isolated device demonstration",
          badge: "Current UI · device demo · 16 Nov 2026",
          provenance: "Current UI · device demo · 16 Nov 2026",
          title: "Review before you register.",
          caption: "The current notice explains information use before a phone number is submitted for registration. This isolated demonstration does not create an account.",
        },
        motion: {
          src: "/internal/app-showcase/media/active-weather-sharing.mp4",
          poster: "/internal/app-showcase/media/location-sharing.png",
          badge: "Current UI · device demo · 16 Nov 2026",
          provenance: "Current UI · device demo · 16 Nov 2026",
          title: "Choose when to share.",
          caption: "Review the forecast, then compare separate sharing-off and demonstration sharing-on views on a sample Penang map. No real sharing link is created or activated.",
        },
      },
    },
    {
      id: "future",
      date: "Future direction",
      era: "The next horizon",
      title: "The circle reaches farther",
      lead: "What if essential trail tools could reach your wrist, a nearby hiker, or a radio network beyond mobile coverage? Explore three directions from the project’s final report.",
      concept: true,
      features: [
        ["A smartwatch companion", "Hike progress, warnings and SOS confirmation could move to a compatible watch."],
        ["Nearby Bluetooth support", "Private SOS forwarding and offline team readiness could extend the app’s existing Bluetooth tools."],
        ["A LoRa trail network", "Portable radio nodes could relay short SOS messages and coordinates towards a connected gateway."],
      ],
      shot: ["A possible connected trail kit", "An illustrated exploration of the smartwatch, Bluetooth and LoRa recommendations."],
      motion: ["Explore the connections", "Compare three proposals and what changes when a connection is unavailable."],
    },
  ];

  const loadCommunityStats = async () => {
    if (!statsRegion) return;
    const trailRegion = document.querySelector('[data-trail-stats]');
    const trailStatus = document.querySelector('[data-trail-stats-status]');
    const trailKeys = ['totalTrails', 'trailDistanceKm', 'regionsCovered', 'easyTrails', 'moderateTrails', 'hardTrails'];
    try {
      const response = await fetch("/api/public-stats?v=trail-votes", { headers: { Accept: "application/json" } });
      if (!response.ok) throw new Error(`Stats request failed with ${response.status}`);
      const stats = await response.json();
      if (trailRegion && trailKeys.every(key => Number.isFinite(stats.trails?.[key]) && stats.trails[key] >= 0)) {
        trailKeys.forEach(key => {
          const formatter = key === 'trailDistanceKm' ? distanceFormatter : integerFormatter;
          trailRegion.querySelector(`[data-trail-stat="${key}"]`).textContent = formatter.format(stats.trails[key]);
        });
        trailRegion.classList.add('is-loaded');
        if (trailStatus) {
          const unclassified = stats.trails.totalTrails - stats.trails.easyTrails - stats.trails.moderateTrails - stats.trails.hardTrails;
          trailStatus.textContent = 'Each listed trail is counted once. Distance adds route lengths, not hiker activity. Coverage is across Malaysia.' +
            ' Difficulty is based on hikers’ post-hike votes.' +
            (unclassified > 0 ? ` ${integerFormatter.format(unclassified)} ${unclassified === 1 ? 'trail is' : 'trails are'} awaiting difficulty votes.` : '');
        }
      }
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
      trailRegion?.removeAttribute('aria-busy');
      if (trailStatus && !trailRegion?.classList.contains('is-loaded')) {
        trailStatus.textContent = 'Trail totals are temporarily unavailable. Please check again shortly.';
      }
    }
  };

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
      document.querySelector('[data-beta-checksum]').textContent = `Download verification · SHA-256: ${release.sha256}`;
    } catch (_) {
      link.textContent = 'Download temporarily unavailable';
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
    const footer = milestoneDialog.querySelector(".milestone-dialog-footer");
    if (footer) footer.hidden = Boolean(story.concept);

    setMilestoneText("[data-milestone-count]", story.concept ? "Future recommendations" : `Milestone ${number} of ${milestoneStories.length}`);
    setMilestoneText("[data-milestone-date]", story.date);
    setMilestoneText("[data-milestone-era]", story.era);
    setMilestoneText("[data-milestone-title]", story.title);
    setMilestoneText("[data-milestone-lead]", story.lead);
    setMilestoneText("[data-milestone-footer-number]", number);
    setMilestoneText("[data-milestone-footer-total]", String(milestoneStories.length));
    setMilestoneText("[data-milestone-shot-title]", story.shot[0]);
    setMilestoneText("[data-milestone-shot-brief]", story.shot[1]);
    setMilestoneText("[data-milestone-motion-title]", story.motion[0]);
    setMilestoneText("[data-milestone-motion-brief]", story.motion[1]);

    const media = story.media;
    const videoPlaceholders = Boolean(media?.videoPlaceholders);
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
    setMilestoneText("[data-milestone-shot-label]", videoPlaceholders ? "Screen recording slot" : "Screenshot slot");
    setMilestoneText("[data-milestone-shot-format]", videoPlaceholders ? "Phone portrait" : "Portrait");
    setMilestoneText("[data-milestone-shot-icon]", videoPlaceholders ? "▶" : "01");
    setMilestoneText("[data-milestone-shot-status]", videoPlaceholders ? "Recording needed" : "Awaiting final media");
    setMilestoneText("[data-milestone-motion-format]", videoPlaceholders ? "Phone portrait" : "10–15 sec");
    setMilestoneText("[data-milestone-motion-status]", videoPlaceholders ? "Recording needed" : "Awaiting final media");
    setMilestoneText("[data-milestone-media-heading]", story.concept ? "Beyond the phone. Still within the circle." : media?.heading || "Prepared for the real product story.");
    const futureLab = milestoneDialog.querySelector("[data-future-lab]");
    if (futureLab) futureLab.hidden = !story.concept;
    const futureArt = milestoneDialog.querySelector("[data-future-art]");
    if (futureArt) futureArt.hidden = !story.concept;
    const achievements = milestoneDialog.querySelector(".milestone-achievements");
    if (achievements) achievements.hidden = Boolean(story.concept);
    const mediaHeading = milestoneDialog.querySelector(".milestone-media > .milestone-section-heading");
    if (mediaHeading) mediaHeading.hidden = Boolean(story.concept);
    if (mediaGrid) mediaGrid.hidden = Boolean(story.concept);
    if (story.concept) resetFutureConcept();
    if (mediaDescription) {
      const description = story.concept ? "Tap each link to explore one possible future safety network—not a preview of an existing product." : media ? media.description : "These media slots can be replaced with final screenshots or clips later without changing the layout.";
      mediaDescription.textContent = description || "";
      mediaDescription.hidden = !description;
    }
    setMilestoneText("[data-milestone-media-badge]", screenshot?.provenance || screenshot?.badge || "");
    setMilestoneText("[data-milestone-media-caption-title]", screenshot?.title || "");
    setMilestoneText("[data-milestone-media-caption]", screenshot?.caption || "");
    setMilestoneText("[data-milestone-motion-badge]", motion?.provenance || motion?.badge || "");
    setMilestoneText("[data-milestone-motion-caption-title]", motion?.title || "");
    setMilestoneText("[data-milestone-motion-caption]", motion?.caption || "");
    mediaGrid?.classList.toggle("has-single-media", hasRealMedia && hasScreenshot !== hasMotion);
    mediaGrid?.classList.toggle("has-media-pair", hasScreenshot && hasMotion);
    mediaGrid?.classList.toggle("has-video-placeholders", videoPlaceholders);
    shotSlot?.classList.toggle("milestone-media-slot-motion", videoPlaceholders);
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
    if (conceptNote) {
      conceptNote.hidden = !story.concept;
      conceptNote.textContent = "Research concepts · not included in the beta";
    }
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

  const futureSteps = [
    {
      id: "watch", kicker: "01 / SMARTWATCH", tag: "On your wrist",
      title: "Progress at a glance. Safety within reach.",
      copy: "A proposed watch companion could show hike progress, warnings and SOS confirmation. A compatible GPS watch could also record footprints while reducing reliance on the phone’s battery.",
      capabilities: ["Hike progress and warnings on the wrist", "A deliberate SOS confirmation step", "GPS footprint recording on supported watches"],
      nodes: [["watch", "Your watch", "Progress at a glance"], ["route", "GPS footprints", "A record of your path"], ["shield", "SOS controls", "Confirm an action"]],
      scene: "Three proposed watch capabilities. This is an illustration, not a working watch app.",
      toggle: "Show phone disconnected",
      outcome: ["A companion to the phone", "The watch, phone and backend would need a tested connection for actions that send or synchronise information."],
      offline: ["Recording is not delivery", "A GPS-equipped watch could record a route locally, but synchronisation and SOS delivery may wait for a usable connection. An on-screen confirmation would not prove a contact received it."],
    },
    {
      id: "nearby", kicker: "02 / NEARBY BLUETOOTH", tag: "Help from nearby devices",
      title: "A nearby phone could carry the next step.",
      copy: "The report proposes letting an internet-connected HikerCircle phone privately forward an otherwise failed SOS. A second extension would let nearby teammates exchange pre-hike readiness offline and reconcile it later.",
      capabilities: ["Private forwarding without exposing contact details to the helper", "Offline exchange of pre-hike team readiness", "Reconciliation after reconnecting to prevent duplicate records"],
      nodes: [["phone", "Your phone", "An SOS cannot send"], ["relay", "Nearby phone", "A compatible helper"], ["cloud", "Internet connection", "Forward to the service"]],
      scene: "A proposed SOS relay. Offline team readiness is a separate nearby exchange.",
      toggle: "No connected helper nearby",
      outcome: ["A possible alternate route", "A compatible nearby phone would need Bluetooth reach and its own internet connection. The relay should keep sender and recipient details private."],
      offline: ["Relay unavailable", "Without a compatible connected helper, this route cannot forward the SOS. Nearby hikers alone do not establish connectivity or prove that help is on the way."],
    },
    {
      id: "lora", kicker: "03 / LORA TRAIL NETWORK", tag: "Beyond mobile coverage",
      title: "Small messages. A longer trail connection.",
      copy: "Portable LoRa accessories could carry a short SOS and coordinates between radio nodes. A phone would connect to its accessory over Bluetooth; a gateway or connected phone would provide the route back to the online service.",
      capabilities: ["Portable radio hardware carried with the phone", "Short SOS and coordinate packets across LoRa relays", "A connected gateway to pass messages onward"],
      nodes: [["phone", "Phone + radio", "Bluetooth to an accessory"], ["relay", "LoRa relays", "Short radio messages"], ["gateway", "Connected gateway", "An internet route out"]],
      scene: "Proposed radio path. Terrain, power and node placement would determine reach.",
      toggle: "Show gateway offline",
      outcome: ["The gateway is a bridge", "Radio reach alone is not internet delivery. A reachable gateway or connected phone would still be needed to forward a message to the service."],
      offline: ["No route to the online service", "A radio packet might reach another node while the gateway remains offline. Delivery must stay unconfirmed until the system has evidence; there is no full-coverage or rescue guarantee."],
    },
  ];
  let futureStep = 0;
  const futureButtons = [...document.querySelectorAll("[data-future-step]")];
  const futureOffline = document.querySelector("[data-future-offline]");
  const renderFutureConcept = (step) => {
    futureStep = step;
    const disconnected = Boolean(futureOffline?.checked);
    const topic = futureSteps[step];
    futureButtons.forEach((button, index) => {
      button.setAttribute("aria-selected", String(index === step));
      button.tabIndex = index === step ? 0 : -1;
    });
    const panel = milestoneDialog?.querySelector("#future-concept-panel");
    if (panel) {
      panel.dataset.futureTopic = topic.id;
      panel.setAttribute("aria-labelledby", futureButtons[step].id);
    }
    setMilestoneText("[data-future-kicker]", topic.kicker);
    setMilestoneText("[data-future-tag]", topic.tag);
    setMilestoneText("[data-future-title]", topic.title);
    setMilestoneText("[data-future-copy]", topic.copy);
    setMilestoneText("[data-future-scene-note]", topic.scene);
    setMilestoneText("[data-future-offline-label]", topic.toggle);
    const capabilities = milestoneDialog?.querySelector("[data-future-capabilities]");
    capabilities?.replaceChildren(...topic.capabilities.map(text => {
      const item = document.createElement("li");
      item.textContent = text;
      return item;
    }));
    milestoneDialog?.querySelectorAll("[data-future-node-icon]").forEach((icon, index) => icon.setAttribute("href", `#future-icon-${topic.nodes[index][0]}`));
    milestoneDialog?.querySelectorAll("[data-future-node-title]").forEach((title, index) => { title.textContent = topic.nodes[index][1]; });
    milestoneDialog?.querySelectorAll("[data-future-node-caption]").forEach((caption, index) => { caption.textContent = topic.nodes[index][2]; });
    const outcome = disconnected ? topic.offline : topic.outcome;
    setMilestoneText("[data-future-outcome-title]", outcome[0]);
    setMilestoneText("[data-future-outcome-copy]", outcome[1]);
    milestoneDialog?.querySelector(".future-outcome")?.classList.toggle("is-disconnected", disconnected);
    milestoneDialog?.querySelector("[data-future-scene]")?.classList.toggle("is-disconnected", disconnected);
  };
  const resetFutureConcept = () => {
    if (futureOffline) futureOffline.checked = false;
    renderFutureConcept(0);
  };
  futureButtons.forEach((button, index) => {
    const select = () => {
      if (futureOffline) futureOffline.checked = false;
      renderFutureConcept(index);
    };
    button.addEventListener("click", select);
    button.addEventListener("keydown", event => {
      const next = { ArrowLeft: (index + futureButtons.length - 1) % futureButtons.length, ArrowRight: (index + 1) % futureButtons.length, Home: 0, End: futureButtons.length - 1 }[event.key];
      if (next === undefined) return;
      event.preventDefault();
      futureButtons[next].click();
      futureButtons[next].focus({ preventScroll: true });
    });
  });
  futureOffline?.addEventListener("change", () => renderFutureConcept(futureStep));

  const openMilestone = (id, trigger) => {
    if (!milestoneDialog) return;
    const index = milestoneStories.findIndex((story) => story.id === id);
    if (index < 0) return;
    if (milestoneCloseTimer !== null) window.clearTimeout(milestoneCloseTimer);
    lastMilestoneTrigger = trigger || lastMilestoneTrigger;
    renderMilestone(index);
    milestoneDialog.hidden = false;
    milestonePanel?.scrollTo({ top: 0, behavior: "instant" });
    document.body.classList.add("milestone-dialog-open");
    window.requestAnimationFrame(() => {
      milestoneDialog.classList.add("is-open");
      window.requestAnimationFrame(() => {
        if (!milestoneDialog.hidden) milestoneDialog.querySelector(".milestone-dialog-close")?.focus({ preventScroll: true });
      });
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

  const evolutionElement = (tag, className, value) => {
    const element = document.createElement(tag);
    if (className) element.className = className;
    if (value) element.textContent = value;
    return element;
  };

  const evolutionSlides = (story) => {
    if (story.concept) return [{ kind: "concept", title: "A possible wider circle" }];
    const slides = [];
    if (story.media?.screenshot?.src) {
      slides.push({ kind: "image", ...story.media.screenshot });
    } else if (story.media?.videoPlaceholders) {
      slides.push({ kind: "video-needed", title: story.shot[0], instruction: story.shot[1] });
    }
    if (story.media?.motion?.src) {
      slides.push({ kind: "video", ...story.media.motion });
    } else if (story.motion && slides.length === 0) {
      slides.push({ kind: "video-needed", title: story.motion[0], instruction: story.motion[1] });
    }
    return slides;
  };

  const evolutionTime = (seconds) => {
    if (!Number.isFinite(seconds)) return "0:00";
    const whole = Math.max(0, Math.floor(seconds));
    return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, "0")}`;
  };

  evolutionCards.forEach((card) => {
    const story = milestoneStories.find((item) => item.id === card.dataset.milestone);
    const trigger = card.querySelector("[data-milestone-open]");
    if (!story || !trigger) return;
    const slides = evolutionSlides(story);
    const front = evolutionElement("div", "evolution-card-face evolution-card-front");
    front.append(...card.children);
    const back = evolutionElement("div", "evolution-card-face evolution-card-back");
    back.inert = true;
    back.setAttribute("aria-hidden", "true");
    const inner = evolutionElement("div", "evolution-card-inner");
    inner.append(front, back);
    card.append(inner);
    card.classList.add("is-flippable");

    const triggerText = trigger.querySelector("span:first-child");
    if (triggerText) triggerText.textContent = story.concept ? "View concept" : "View media";
    trigger.setAttribute("aria-label", story.concept ? `View concept: ${story.title}` : `Flip ${story.title} to view its media`);
    if (story.concept) trigger.setAttribute("aria-haspopup", "dialog");
    else trigger.setAttribute("aria-expanded", "false");

    const top = evolutionElement("div", "evolution-card-back-top");
    top.append(evolutionElement("span", "evolution-media-kind"), evolutionElement("span", "evolution-media-count"));
    const returnButton = evolutionElement("button", "evolution-flip-back", "↶");
    returnButton.type = "button";
    returnButton.setAttribute("aria-label", `Return to ${story.title} milestone summary`);
    const stage = evolutionElement("div", "evolution-media-stage");
    const bottom = evolutionElement("div", "evolution-media-bottom");
    const mediaTitle = evolutionElement("h4", "evolution-media-title");
    const navigation = evolutionElement("div", "evolution-media-navigation");
    const previous = evolutionElement("button", "evolution-media-previous", "←");
    previous.type = "button";
    previous.setAttribute("aria-label", `Previous media for ${story.title}`);
    const next = evolutionElement("button", "evolution-media-next", "→");
    next.type = "button";
    next.setAttribute("aria-label", `Next media for ${story.title}`);
    navigation.append(previous, returnButton, next);
    bottom.append(mediaTitle, navigation);
    back.append(top, stage, bottom);

    let slideIndex = 0;
    const renderSlide = (index) => {
      if (!slides.length) return;
      stage.querySelector("video")?.pause();
      slideIndex = (index + slides.length) % slides.length;
      const slide = slides[slideIndex];
      const kindLabel = slide.kind === "image" ? "Screenshot" : slide.kind === "concept" ? "Exploring the future" : slide.kind === "video" ? "Screen recording" : "Video needed";
      top.firstElementChild.textContent = [kindLabel, slide.provenance].filter(Boolean).join(" · ");
      top.lastElementChild.textContent = slides.length > 1 ? `${slideIndex + 1} / ${slides.length}` : "";
      mediaTitle.textContent = slide.title || "HikerCircle in action";
      previous.hidden = slides.length < 2;
      next.hidden = slides.length < 2;
      bottom.querySelector(".evolution-video-player")?.remove();
      bottom.querySelector(".evolution-concept-action")?.remove();
      stage.replaceChildren();

      if (slide.kind === "image") {
        const image = evolutionElement("img", "evolution-media-image");
        image.src = slide.src;
        image.alt = slide.alt || slide.title || "HikerCircle app screenshot";
        image.loading = "lazy";
        stage.append(image);
      } else if (slide.kind === "video") {
        const video = evolutionElement("video", "evolution-media-video");
        video.src = slide.src;
        if (slide.poster) video.poster = slide.poster;
        video.muted = true;
        video.loop = true;
        video.playsInline = true;
        video.preload = "metadata";
        video.setAttribute("aria-label", slide.title || "HikerCircle screen recording");
        stage.append(video);
        const player = evolutionElement("div", "evolution-video-player");
        const playButton = evolutionElement("button", "evolution-video-toggle", "▶");
        playButton.type = "button";
        playButton.setAttribute("aria-label", "Play recording");
        const seek = evolutionElement("input", "evolution-video-seek");
        seek.type = "range";
        seek.min = "0";
        seek.max = "1000";
        seek.value = "0";
        seek.setAttribute("aria-label", "Seek through recording");
        const clock = evolutionElement("span", "evolution-video-time", "0:00 / 0:00");
        player.append(playButton, seek, clock);
        bottom.insertBefore(player, navigation);
        const syncPlayback = () => {
          playButton.textContent = video.paused ? "▶" : "Ⅱ";
          playButton.setAttribute("aria-label", video.paused ? "Play recording" : "Pause recording");
        };
        const syncProgress = () => {
          const fraction = Number.isFinite(video.duration) && video.duration > 0 ? video.currentTime / video.duration : 0;
          seek.value = String(Math.round(fraction * 1000));
          seek.style.setProperty("--played", `${fraction * 100}%`);
          clock.textContent = `${evolutionTime(video.currentTime)} / ${evolutionTime(video.duration)}`;
        };
        const togglePlayback = () => {
          if (video.paused) {
            delete video.dataset.userPaused;
            video.play().catch(syncPlayback);
          } else {
            video.dataset.userPaused = "true";
            video.pause();
          }
        };
        video.addEventListener("play", syncPlayback);
        video.addEventListener("pause", syncPlayback);
        video.addEventListener("timeupdate", syncProgress);
        video.addEventListener("loadedmetadata", syncProgress);
        playButton.addEventListener("click", togglePlayback);
        video.addEventListener("click", togglePlayback);
        seek.addEventListener("input", () => {
          if (Number.isFinite(video.duration)) video.currentTime = video.duration * Number(seek.value) / 1000;
          syncProgress();
        });
        if (card.classList.contains("is-flipped") && !reducedMotion) video.play().catch(syncPlayback);
      } else if (slide.kind === "video-needed") {
        const placeholder = evolutionElement("div", "evolution-media-needed");
        placeholder.append(
          evolutionElement("span", "evolution-needed-icon", "▷"),
          evolutionElement("strong", "", "Recording needed"),
          evolutionElement("p", "", `${slide.instruction} Send a dark-mode phone-portrait clip to add it here.`),
        );
        stage.append(placeholder);
      } else {
        const concept = evolutionElement("div", "evolution-media-concept");
        concept.append(
          evolutionElement("span", "", "IDEA · NOT A RELEASE PROMISE"),
          evolutionElement("strong", "", "A safety message that could travel farther."),
          evolutionElement("p", "", "Watch → nearby hikers → trail gateway → your circle"),
        );
        stage.append(concept);
        const conceptAction = evolutionElement("button", "evolution-concept-action", "Explore the idea ↗");
        conceptAction.type = "button";
        conceptAction.addEventListener("click", () => openMilestone(story.id, conceptAction));
        bottom.insertBefore(conceptAction, navigation);
      }
    };

    trigger.addEventListener("click", (event) => {
      if (suppressMilestoneOpen) {
        event.preventDefault();
        return;
      }
      if (story.concept) {
        openMilestone(story.id, trigger);
        return;
      }
      evolutionRail?.scrollTo({
        left: card.offsetLeft - (evolutionRail.clientWidth - card.offsetWidth) / 2,
        behavior: reducedMotion ? "instant" : "smooth",
      });
      card.classList.add("is-flipped");
      trigger.setAttribute("aria-expanded", "true");
      front.inert = true;
      front.setAttribute("aria-hidden", "true");
      back.inert = false;
      back.removeAttribute("aria-hidden");
      renderSlide(0);
      returnButton.focus({ preventScroll: true });
    });
    returnButton.addEventListener("click", () => {
      stage.querySelector("video")?.pause();
      card.classList.remove("is-flipped");
      trigger.setAttribute("aria-expanded", "false");
      back.inert = true;
      back.setAttribute("aria-hidden", "true");
      front.inert = false;
      front.removeAttribute("aria-hidden");
      trigger.focus({ preventScroll: true });
    });
    previous.addEventListener("click", () => renderSlide(slideIndex - 1));
    next.addEventListener("click", () => renderSlide(slideIndex + 1));
    back.addEventListener("keydown", (event) => {
      if (event.key === "Escape") {
        event.stopPropagation();
        returnButton.click();
        return;
      }
      if (event.target.tagName === "INPUT" || !["ArrowLeft", "ArrowRight"].includes(event.key)) return;
      event.stopPropagation();
      event.preventDefault();
      renderSlide(slideIndex + (event.key === "ArrowRight" ? 1 : -1));
    });
    back.addEventListener("pointerdown", (event) => {
      if (event.target.closest("button, input")) event.stopPropagation();
    });
  });

  if (evolutionRail && "IntersectionObserver" in window) {
    new IntersectionObserver(([entry]) => {
      if (!entry.isIntersecting) evolutionCards.forEach((card) => card.querySelectorAll("video").forEach((video) => video.pause()));
    }, { threshold: 0.1 }).observe(evolutionRail);
  }
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) evolutionCards.forEach((card) => card.querySelectorAll("video").forEach((video) => video.pause()));
  });
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
    const focusable = [...milestoneDialog.querySelectorAll('button:not(:disabled):not([tabindex="-1"]),a[href],input:not(:disabled),select:not(:disabled),textarea:not(:disabled),summary,[tabindex]:not([tabindex="-1"])')]
      .filter(element => !element.closest("[hidden],[inert]") && element.getClientRects().length > 0 && getComputedStyle(element).visibility !== "hidden");
    if (focusable.length === 0) return;
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (!milestoneDialog.contains(document.activeElement)) {
      event.preventDefault();
      (event.shiftKey ? last : first).focus();
    } else if (event.shiftKey && document.activeElement === first) {
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
      const cardVideo = card.querySelector(".evolution-media-stage video");
      if (!current) cardVideo?.pause();
      else if (cardVideo?.paused && cardVideo.dataset.userPaused !== "true" && card.classList.contains("is-flipped") && !reducedMotion) cardVideo.play().catch(() => {});
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
    if (event.target.closest(".evolution-card-back")) return;
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
    const captureCaption = document.querySelector("[data-showcase-capture]");
    if (captureCaption) captureCaption.textContent = scenes[activeIndex]?.dataset.captureCaption || "";
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
  loadBetaDownload();
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
