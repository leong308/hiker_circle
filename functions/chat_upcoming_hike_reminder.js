// Upcoming-hike WhatsApp reminders use canonical schedule data, never client-supplied message text.
'use strict';

// text: Keep user-authored trail/group names on one bounded, readable line.
function text(value, limit = 160) {
  return String(value || '').replace(/[\x00-\x1f\x7f-\x9f\u2028\u2029\u202a-\u202e\u2066-\u2069]/g, ' ')
    .replace(/\s+/g, ' ').trim().slice(0, limit);
}

// millis: Read current Firestore timestamps and older ISO schedule values.
function millis(value) {
  if (typeof value?.toMillis === 'function') return value.toMillis();
  if (typeof value?.toDate === 'function') return value.toDate().getTime();
  if (value instanceof Date) return value.getTime();
  return typeof value === 'number' ? value : Date.parse(value || '');
}

// timeZone: Use the chat's hiking time zone, with the Malaysian app default as fallback.
function timeZone(value) {
  const candidate = text(value, 80) || 'Asia/Kuala_Lumpur';
  try { new Intl.DateTimeFormat('en-GB', {timeZone: candidate}); return candidate; }
  catch (_) { return 'Asia/Kuala_Lumpur'; }
}

// dateLabel: Include the date on overnight hikes and make the display time zone explicit.
function dateLabel(value, zone) {
  const timestamp = millis(value);
  if (!Number.isFinite(timestamp) || !Number.isFinite(new Date(timestamp).getTime())) return '';
  const date = new Intl.DateTimeFormat('en-GB', {timeZone: zone, weekday: 'short',
    day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit',
    hourCycle: 'h23'}).format(new Date(timestamp));
  return `${date} (${zone === 'Asia/Kuala_Lumpur' ? 'MYT' : zone})`;
}

// buildUpcomingHikeReminder: Format only public hike arrangements and the named group chat.
function buildUpcomingHikeReminder({hike, chatName, zone}) {
  const displayZone = timeZone(zone || hike.timeZone);
  const departure = dateLabel(hike.departureTimeLocal || hike.departureTime, displayZone);
  if (!departure) throw new Error('upcoming-hike-departure-missing');
  const returning = dateLabel(hike.expectedReturnTimeLocal || hike.expectedReturnTime, displayZone);
  const start = text(hike.startPointName);
  const places = [...new Map([hike.area, hike.state, hike.country].map(value => text(value))
    .filter(Boolean).map(value => [value.toLowerCase(), value])).values()];
  const distance = Number(hike.distanceKm), minutes = Number(hike.durationMinutes);
  const lines = ['HikerCircle — Upcoming hike reminder', '',
    `Trail: ${text(hike.trailName) || 'Upcoming hike'}`, `Departure: ${departure}`];
  if (returning) lines.push(`Estimated latest arrival: ${returning}`);
  if (start) lines.push(`Starting point: ${start}`);
  if (places.length) lines.push(`Location: ${places.join(', ')}`);
  if (Number.isFinite(distance) && distance > 0) lines.push(`Trail distance: ${Number(distance.toFixed(1))} km`);
  if (Number.isFinite(minutes) && Math.round(minutes) > 0) {
    const total = Math.round(minutes), hours = Math.floor(total / 60), rest = total % 60;
    lines.push(`Estimated hiking duration: ${[hours ? `${hours} hr` : '', rest ? `${rest} min` : ''].filter(Boolean).join(' ')}`);
  }
  lines.push('', `Open HikerCircle to review the latest messages and hike arrangements in '${text(chatName, 100) || 'HikerCircle hike'}' group chat.`);
  return lines.join('\n');
}

module.exports = {buildUpcomingHikeReminder};
