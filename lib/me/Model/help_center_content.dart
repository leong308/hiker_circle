/// Offline help content. Condition identifiers also cover map caution types and
/// the labels hikers can choose when reporting a hazard.
class TrailConditionGuide {
  const TrailConditionGuide(
    this.title,
    this.category,
    this.meaning,
    this.action, {
    this.types = const [],
  });

  final String title, category, meaning, action;
  final List<String> types;
}

const trailConditionGuides = <TrailConditionGuide>[
  TrailConditionGuide(
    'Slippery pathway',
    'Ground',
    'Wet rock, roots or leaves can reduce grip.',
    'Slow down, use grippy footwear and test each step. Turn back if you cannot keep your footing.',
  ),
  TrailConditionGuide(
    'Loose rock',
    'Ground',
    'Loose stones, gravel or scree can move underfoot.',
    'Take deliberate steps, leave space and avoid knocking stones onto hikers below.',
    types: ['loose_rock'],
  ),
  TrailConditionGuide(
    'Deep mud',
    'Ground',
    'Soft ground can hide holes and become harder to pass after rain.',
    'Use grippy shoes and check footing. Turn back if it is too deep; avoid widening the trail.',
    types: ['muddy_surface'],
  ),
  TrailConditionGuide(
    'Rough or uneven ground',
    'Ground',
    'Roots, rocks and broken ground need extra balance and time.',
    'Watch your next step, slow your pace and choose a route suited to the whole group.',
    types: ['rough_surface'],
  ),
  TrailConditionGuide(
    'Ice or snow',
    'Ground',
    'Frozen surfaces can hide the path and make falls difficult to stop.',
    'Choose another route unless you have suitable equipment and winter skills. Avoid uncertain snow bridges.',
  ),
  TrailConditionGuide(
    'Steep ascent',
    'Terrain',
    'A sharp uphill section takes more effort than level walking.',
    'Use a steady pace, take breaks and allow extra time. Turn back before the group becomes exhausted.',
    types: ['steep_ascent'],
  ),
  TrailConditionGuide(
    'Steep descent',
    'Terrain',
    'A sharp downhill section increases the chance of slipping.',
    'Take short, controlled steps and leave space. Avoid running or taking shortcuts.',
    types: ['steep_descent'],
  ),
  TrailConditionGuide(
    'Steep terrain',
    'Terrain',
    'The route crosses steep ground; difficulty depends on direction and footing.',
    'Check the slope ahead and use marked paths. Choose another route if anyone is uncomfortable.',
    types: ['steep_section'],
  ),
  TrailConditionGuide(
    'Cliff or exposed edge',
    'Terrain',
    'There may be a sudden drop beside the path.',
    'Stay well back from edges and follow barriers. Avoid exposed sections in wind or poor visibility.',
    types: ['cliff'],
  ),
  TrailConditionGuide(
    'Scrambling section',
    'Terrain',
    'You may need your hands to move over rocks or exposed ground.',
    'Proceed only within your experience, with secure footing. Turn back if the moves or exposure feel unsafe.',
    types: ['scrambling_section'],
  ),
  TrailConditionGuide(
    'River or stream nearby',
    'Water',
    'Map data shows water near the route, which may not require a crossing.',
    'Check the actual path and recent rain. A water marker does not confirm a safe crossing or wildlife presence.',
    types: ['river', 'stream', 'stream_intermittent'],
  ),
  TrailConditionGuide(
    'River ford',
    'Water',
    'The route may pass through water without a bridge.',
    'Do not enter fast, rising or unclear water. Use a safe alternative or turn back if uncertain.',
    types: ['ford_crossing'],
  ),
  TrailConditionGuide(
    'Stepping stones',
    'Water',
    'A crossing uses stones that may be wet, loose or submerged.',
    'Check flow and footing from the bank. Turn back if stones are submerged or the crossing is uncertain.',
    types: ['stepping_stones'],
  ),
  TrailConditionGuide(
    'Bridge crossing',
    'Water',
    'A bridge is mapped on the route; its present condition is not confirmed.',
    'Follow posted limits and inspect from safe ground. Do not use damaged or flooded bridges.',
    types: ['bridge_crossing'],
  ),
  TrailConditionGuide(
    'Flooded route',
    'Water',
    'Water covers the path and can hide strong currents or missing ground.',
    'Do not wade through floodwater. Move to safe higher ground and choose another route.',
  ),
  TrailConditionGuide(
    'Fast river crossing',
    'Water',
    'Strong or rising flow can sweep a hiker off their feet.',
    'Do not cross. Turn back or use an open, intact bridge on an approved route.',
  ),
  TrailConditionGuide(
    'Damaged bridge',
    'Water',
    'The deck, rails or supports may no longer hold safely.',
    'Stay off the bridge. Report it from safe ground and follow an official diversion.',
  ),
  TrailConditionGuide(
    'Fallen tree',
    'Obstacles',
    'A tree or large branch blocks the path and may still move.',
    'Keep away from hanging branches. Use an official diversion or turn back rather than climbing unstable timber.',
  ),
  TrailConditionGuide(
    'Landslide',
    'Obstacles',
    'Earth or rock has moved across the route and may move again.',
    'Keep clear of the slope and debris. Turn back and report the location when safe.',
  ),
  TrailConditionGuide(
    'Closed trail',
    'Obstacles',
    'Access is restricted for safety, maintenance or conservation.',
    'Respect barriers and notices. Choose an open route; do not bypass the closure.',
  ),
  TrailConditionGuide(
    'Other obstruction',
    'Obstacles',
    'An unexpected object or damaged section blocks progress.',
    'Stop before the obstacle. Use a marked alternative or turn back and report it.',
  ),
  TrailConditionGuide(
    'Rope-assisted section',
    'Structures',
    'A fixed rope or aid is mapped on a steep section.',
    'A rope is not a safety guarantee. Avoid damaged aids and turn back if the section exceeds your skills.',
    types: ['rope_assisted_section'],
  ),
  TrailConditionGuide(
    'Ladder or rungs',
    'Structures',
    'The route uses a ladder or fixed steps on steep ground.',
    'Keep three points of contact and follow posted limits. Avoid loose or damaged equipment.',
    types: ['ladder_section'],
  ),
  TrailConditionGuide(
    'Damaged steps',
    'Structures',
    'Broken, missing or loose steps can cause a fall.',
    'Slow down and avoid unstable steps. Turn back if there is no secure way through.',
  ),
  TrailConditionGuide(
    'Unsafe ladder or rope',
    'Structures',
    'An aid is reported as damaged, loose or unreliable.',
    'Do not use it or try a makeshift repair. Turn back and report the damage.',
  ),
  TrailConditionGuide(
    'Missing sign',
    'Structures',
    'A junction or route marker is missing or unclear.',
    'Stop at the last known point and check your map. Do not guess a route into unfamiliar terrain.',
  ),
  TrailConditionGuide(
    'Wild animal sighting',
    'Wildlife',
    'An animal has been seen nearby; it may still be in the area.',
    'Give it space, never feed or approach it, and follow local ranger advice for that species.',
  ),
  TrailConditionGuide(
    'Snakes',
    'Wildlife',
    'A snake may be on the path or hidden near rocks and vegetation.',
    'Keep your distance and let it move away. Do not touch it or reach into places you cannot see.',
  ),
  TrailConditionGuide(
    'Stinging insects',
    'Wildlife',
    'Bees, wasps or a nest may be close to the path.',
    'Keep away from nests and leave the area calmly. Carry prescribed allergy medicine if you need it.',
  ),
  TrailConditionGuide(
    'Rain or thunderstorms',
    'Weather',
    'Rain reduces grip; storms bring lightning and rapidly rising water.',
    'Check warnings before leaving. At thunder, seek a substantial building or enclosed vehicle; avoid ridges and isolated trees.',
  ),
  TrailConditionGuide(
    'Heat and humidity',
    'Weather',
    'Hot, humid conditions make exertion harder and cooling less effective.',
    'Start in cooler hours, drink regularly and rest in shade. Stop if unwell and get help if symptoms are severe.',
  ),
  TrailConditionGuide(
    'Strong wind',
    'Weather',
    'Gusts affect balance and can bring down branches.',
    'Avoid exposed ridges and damaged trees. Postpone the hike if wind makes progress unsafe.',
  ),
  TrailConditionGuide(
    'Cold or wet conditions',
    'Weather',
    'Wet clothes and wind can cool you quickly, even in mild weather.',
    'Carry dry layers and rain protection. Seek shelter and change wet clothing before you become chilled.',
  ),
  TrailConditionGuide(
    'Poor visibility',
    'Weather',
    'Fog, heavy rain or darkness makes markers and edges harder to see.',
    'Keep the group together, slow down and check your position. Stop or turn back if the route is unclear.',
  ),
  TrailConditionGuide(
    'Sun exposure and UV',
    'Weather',
    'Open sections may have little shade, even on cloudy days.',
    'Use sunscreen, a hat and protective clothing. Plan shade breaks and carry enough water.',
  ),
  TrailConditionGuide(
    'Sunset or low light',
    'Weather',
    'You may run out of daylight before finishing the route.',
    'Set a turnaround time and carry a headlamp. Start earlier or choose a shorter trail.',
  ),
  TrailConditionGuide(
    'Unsafe human activity',
    'Other',
    'Threatening behaviour or dangerous activity has been reported.',
    'Keep your distance, avoid confrontation and leave safely. Contact emergency services if there is immediate danger.',
  ),
  TrailConditionGuide(
    'Other',
    'Other',
    'A caution does not fit the listed conditions, or its details are uncertain.',
    'Read the report, assess from a safe place and turn back if unsure. Add a clear description when reporting.',
    types: ['generic'],
  ),
];

class HelpArticle {
  const HelpArticle(
    this.title,
    this.text, {
    this.location,
    this.actions = const [],
    this.tip,
  });
  final String title, text;
  final String? location, tip;
  final List<String> actions;
}

const planningHelp = [
  HelpArticle(
    'Find a suitable trail',
    'On Home, use All, Nearest or State to browse. Open a trail and compare distance, duration, elevation and cautions with your experience.',
  ),
  HelpArticle(
    'Read the map',
    'Review checkpoints and the route preview before setting off. Mapped cautions are planning clues; community reports describe what another hiker observed. Check dates and on-site signs.',
  ),
  HelpArticle(
    'Check the forecast',
    'Review the forecast for your whole planned hike, including the return. Missing or saved data does not mean conditions are safe. Recheck near departure.',
  ),
  HelpArticle(
    'Pack and prepare',
    'Complete the preparation checklist. Bring water, food, rain protection, a headlamp and a charged phone. Tell someone your route and expected return time.',
  ),
  HelpArticle(
    'While hiking',
    'Follow the marked route and monitor your progress. Allow time to return, keep the group together and turn back when conditions exceed your ability.',
  ),
  HelpArticle(
    'Finish and review',
    'End the hike in the app, then review Hike History from your profile. Check the sharing preview before choosing to publish.',
  ),
  HelpArticle(
    'When there is no signal',
    'Some previously loaded trail information may remain available. Weather updates, messages and SOS delivery need connectivity. Carry a backup map and a plan for getting help.',
  ),
];

const teamHelp = [
  HelpArticle(
    'Create or join a hike',
    'Choose a team and a route that suit everyone’s experience.',
    location: 'Home → Find a Hike · or create a Group hike',
    actions: [
      'Check the host, departure, route and available places.',
      'Join an open hike or send a request when approval is required.',
      'Wait for acceptance before treating a pending request as a place.',
    ],
    tip: 'A join request is not a confirmed place until the host accepts it.',
  ),
  HelpArticle(
    'Coordinate in Circle',
    'Use the hike chat to settle the details before meeting.',
    location: 'Circle → Hike group chat',
    actions: [
      'Agree on the meeting point, pace and expected return.',
      'Share equipment needs and tell the host about any limits.',
      'Check the latest messages if the host changes the plan.',
    ],
    tip: 'Accepted participants can access the related hike chat.',
  ),
  HelpArticle(
    'Get ready together',
    'Each participant completes their own preparation and safety setup.',
    location: 'Team launch → READY',
    actions: [
      'Open your team invitation and review the shared trail.',
      'Read the precautions and complete the required safety settings.',
      'Send READY only when you and your equipment are ready.',
    ],
    tip:
        'Returning from phone Settings should resume your preparation. Check the permission result before continuing.',
  ),
  HelpArticle(
    'Start as one team',
    'The host starts the shared hike after everyone sends READY.',
    location: 'Team launch → START HIKE (host)',
    actions: [
      'Host: check that every included participant is ready.',
      'Resolve unopened invitations; remove pending buddies only after agreeing with them.',
      'Participants: wait for the host and the shared countdown.',
    ],
    tip:
        'Sending READY does not start tracking. Wait until the active hike screen appears.',
  ),
  HelpArticle(
    'Stay together',
    'Match the pace to the group and make route decisions together.',
    location: 'Active hike → Team tools',
    actions: [
      'Agree who leads and who stays at the back.',
      'Regroup at junctions and check on slower members.',
      'Tell the team before stopping, leaving or changing the route.',
    ],
    tip: 'A location dot is not a substitute for checking on a teammate.',
  ),
  HelpArticle(
    'Location and check-ins',
    'Use team updates alongside an agreed plan for weak coverage.',
    location: 'Active hike → Safety settings / Check-in',
    actions: [
      'Check location permissions and sharing settings before departure.',
      'Look at the time of the last update before relying on a position.',
      'Agree on regroup points and what to do if someone loses signal.',
    ],
    tip:
        'GPS, connectivity and phone power can delay updates. A missing update does not prove someone is safe or in danger.',
  ),
  HelpArticle(
    'Finish and reconnect',
    'Confirm everyone has returned and close your tracking session.',
    location: 'Active hike → End hike · Profile → Hike History',
    actions: [
      'Regroup and let the team know you have returned.',
      'End your hike in the app and check the saved summary.',
      'Review your recorded path and sharing preview before publishing.',
    ],
    tip:
        'Check your own tracking status; do not assume another hiker ending their session has ended yours.',
  ),
];

const sosHelp = [
  HelpArticle(
    'Set up before leaving',
    'Prepare your contacts and phone while you have time and signal.',
    location: 'SOS → Emergency contacts · Hike safety settings',
    actions: [
      'Check contact numbers and agree how they should respond.',
      'Allow the location, notification and Bluetooth permissions you need.',
      'Check phone power and the safety setup shown by the app.',
    ],
    tip:
        'Your contacts should know your route and expected return before you leave.',
  ),
  HelpArticle(
    'Practise safely',
    'Learn the controls using the dedicated demos and tests.',
    location: 'SOS → Manual & Duress guide / Test settings',
    actions: [
      'Use the gesture demo to practise tapping and holding without sending an SOS.',
      'Warn contacts before using the WhatsApp test message.',
      'Siren tests make noise; the BLE broadcast test can alert nearby phones.',
    ],
    tip:
        'Tests have different effects. Read the test description; never trigger a real SOS just to practise.',
  ),
  HelpArticle(
    'Physical SOS button',
    'A paired button can start the phone’s Manual SOS workflow.',
    location: 'SOS → Paired SOS button',
    actions: [
      'Follow pairing and the physical confirmation instructions.',
      'Keep the button powered, Bluetooth on and the phone in range.',
      'Enter the dedicated button test mode before a test press; wait for “Test mode active”.',
    ],
    tip:
        'Outside the confirmed test window, a valid button press may trigger a real SOS.',
  ),
  HelpArticle(
    'Manual SOS',
    'Tap and release the emergency control when you need help.',
    location: 'SOS → Emergency SOS',
    actions: [
      'A 10-second cancel window opens; cancel an accidental tap in that window.',
      'After the countdown, the app starts its phone alarm and flashlight while notifying contacts.',
      'Check the delivery status and seek direct emergency help when possible.',
    ],
    tip:
        'Holding the same control has a different effect: it activates Duress SOS.',
  ),
  HelpArticle(
    'Duress SOS',
    'Use a discreet alert when you cannot speak safely.',
    location: 'SOS → Hold the emergency control',
    actions: [
      'Hold continuously for about one second to activate Duress.',
      'The alert sends without the loud alarm or a cancel countdown.',
      'Contacts are warned that calling you could increase danger.',
    ],
    tip:
        'Releasing early starts the Manual SOS cancel window. Practise this distinction in the gesture demo.',
  ),
  HelpArticle(
    'Medical and automatic alerts',
    'Understand the safety features enabled for your hike.',
    location: 'SOS → Safety Tools · Active hike → Safety settings',
    actions: [
      'Review Medical SOS and any fall or stillness detection settings before leaving.',
      'Respond to a safety countdown when prompted; confirm you are safe only when you are.',
      'Do not wait for a sensor to detect an emergency—use Manual SOS or direct help when needed.',
    ],
    tip:
        'Phone movement and OS restrictions affect detection. These features cannot detect every emergency.',
  ),
  HelpArticle(
    'Check alert delivery',
    'Read the alert status, not just the animation or phone alarm.',
    location: 'SOS → Alert status / Queued dispatches',
    actions: [
      'Check whether contacts were notified, delivery is partial or dispatches are queued.',
      'Queued dispatches retry when delivery becomes available; they cannot be removed from the queue screen.',
      'Nearby SOS and local alarms may attract attention, but do not guarantee a response.',
    ],
    tip:
        '“Sent” does not confirm a contact has read the alert or that rescuers are on the way.',
  ),
  HelpArticle(
    'Get emergency help',
    'For immediate danger in Malaysia, call 999 when possible.',
    location: 'Phone → Emergency call',
    actions: [
      'Explain what happened and how many people need help.',
      'Give your coordinates, trail name and nearby landmarks.',
      'Follow the dispatcher’s instructions and update your contacts when safe.',
    ],
    tip:
        'Outside Malaysia, use the local emergency number. HikerCircle does not replace emergency services.',
  ),
];

const accountHelp = [
  HelpArticle(
    'Login and verification',
    'Sign in with your registered number and the method requested on screen.',
    location: 'Sign in → Verification',
    actions: [
      'Check the country code and registered phone number.',
      'Use the newest verification code; an older code may no longer work.',
      'Never share a password, one-time code or authenticator code.',
    ],
    tip:
        'Repeated failures: check the on-screen message and wait for any resend timer before trying again.',
  ),
  HelpArticle(
    'Enter a verification code',
    'Use the code input’s paste or autofill option when available.',
    location: 'Verification → Code field',
    actions: [
      'Return to HikerCircle and tap the code field.',
      'Paste the code if your keyboard does not offer it automatically.',
      'If it expired, request a new code and use only that code.',
    ],
    tip:
        'Keyboard suggestions vary by phone and message app. Never include codes in feedback screenshots.',
  ),
  HelpArticle(
    'Manage login security',
    'Keep a usable verification method before changing phones.',
    location: 'Profile → App Settings → Login security',
    actions: [
      'Review the Authenticator and passkey options supported on your device.',
      'Complete any recent-login verification before changing a method.',
      'Confirm a new method works before removing your previous one.',
    ],
    tip: 'Passkey availability depends on the device and this app build.',
  ),
  HelpArticle(
    'Forgot your password?',
    'Recover access through a method already linked to your account.',
    location: 'Sign in → Forgot Password',
    actions: [
      'Enter your registered number and verify the latest reset code.',
      'Follow an available linked recovery method shown by the app.',
      'Set a new password and return to sign in.',
    ],
    tip:
        'A reset code alone may not finish recovery. Follow the next verification step shown.',
  ),
  HelpArticle(
    'Location and notifications',
    'Check phone permissions when tracking or alerts are delayed.',
    location: 'Phone Settings → HikerCircle · Profile → App Settings',
    actions: [
      'Enable location and Precise Location where offered; allow background access when safety setup requests it.',
      'Allow notifications and Bluetooth for the features you use.',
      'Return to the app and check the permission result; finish any remaining setup.',
    ],
    tip:
        'GPS can be less accurate under dense trees, near cliffs or between tall buildings.',
  ),
  HelpArticle(
    'Weather is not refreshing',
    'A failed refresh can leave the last saved forecast visible.',
    location: 'Active hike → Weather along your hike',
    actions: [
      'Read the last updated time before relying on the forecast.',
      'Active-hike weather refreshes at 15-minute intervals; reopening the sheet does not need a fresh request.',
      'If there is no saved forecast, check connectivity and try again when available.',
    ],
    tip:
        'A saved forecast describes an earlier update. Missing rain data does not mean no rain.',
  ),
  HelpArticle(
    'Weak signal or delayed sync',
    'Some saved information stays available when the connection drops.',
    location: 'Active hike · Hike History · Circle',
    actions: [
      'Check internet access and the time of the last update.',
      'Allow pending updates to sync when coverage returns.',
      'Avoid reinstalling or clearing app data during a hike or while records are pending.',
    ],
    tip:
        'Weather refreshes, chats and cloud SOS delivery need connectivity. Keep a backup plan.',
  ),
  HelpArticle(
    'Report an app problem',
    'Send enough detail to help us reproduce the issue.',
    location: 'Profile → Help Center → Report a problem',
    actions: [
      'Describe what you tried, what you expected and what happened.',
      'Use Mark a screenshot to show the affected screen, if useful.',
      'Remove passwords, codes and private details; check replies through the Feedback history icon.',
    ],
    tip:
        'Feedback is private support for app issues. Use emergency help for immediate danger.',
  ),
];
