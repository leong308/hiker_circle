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
  const HelpArticle(this.title, this.text);
  final String title, text;
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
    'Open Find a Hike to browse upcoming hikes. Some groups allow immediate joining; others need the host to approve your request.',
  ),
  HelpArticle(
    'Coordinate in Circle',
    'Use buddies and the hike group chat to agree on the meeting point, pace, equipment and return time. Accepted participants can access the related hike chat.',
  ),
  HelpArticle(
    'Get ready together',
    'When the host opens team preparation, complete your checks and tap Ready. The host starts the active team hike when everyone is ready.',
  ),
  HelpArticle(
    'Stay together',
    'Agree who leads and who stays at the back. Regroup at junctions, check on slower members and tell the group before changing plans.',
  ),
  HelpArticle(
    'Location and check-ins',
    'Agree when to check in and review location-sharing permissions before departure. A delayed or missing location update does not confirm where someone is.',
  ),
];

const sosHelp = [
  HelpArticle(
    'Set up before leaving',
    'Add and check your emergency contacts. Review location, notification and Bluetooth permissions for the SOS features you use. Keep your phone charged.',
  ),
  HelpArticle(
    'Manual SOS',
    'Open SOS and follow the on-screen confirmation. Check the alert status; sending an alert does not guarantee that a contact has received it or that help is on the way.',
  ),
  HelpArticle(
    'Local alerts and nearby hikers',
    'Local phone alerts may draw attention, and nearby SOS information may help other hikers notice an incident. Neither guarantees that someone nearby can respond.',
  ),
  HelpArticle(
    'Duress',
    'Duress SOS sends a discreet alert without the loud emergency pattern. It tells contacts you may be unable to speak safely. Use the dedicated test settings to practise; do not trigger a real alert as a test.',
  ),
  HelpArticle(
    'Physical SOS button',
    'Pair a supported button from SOS and follow its setup instructions. Keep Bluetooth enabled and the phone in range. Check the configured actions before leaving.',
  ),
  HelpArticle(
    'Get emergency help',
    'In immediate danger, call the local emergency number when possible. In Malaysia, call 999 or 112. Share your location, what happened and how many people need help.',
  ),
];

const accountHelp = [
  HelpArticle(
    'Login and verification',
    'Use your password and the verification method requested on screen. Never share passwords, one-time codes or authenticator codes.',
  ),
  HelpArticle(
    'Manage login security',
    'Go to Profile → App Settings → Login security to manage supported verification methods. Keep a working method available before changing devices.',
  ),
  HelpArticle(
    'Forgot your password?',
    'Use Forgot Password on the sign-in page. Verify the latest reset code, then follow a recovery method already linked to your account.',
  ),
  HelpArticle(
    'Permissions and delayed updates',
    'Check internet access and the relevant phone permission when location, notifications or messages are not updating. Reopen the affected page and check again.',
  ),
  HelpArticle(
    'Report an app problem',
    'Use Feedback below. Include what you tried, what you expected and what happened. Remove passwords, verification codes and private information from screenshots.',
  ),
];
