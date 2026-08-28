'use strict';

function stringValue(value, maximumLength = 500) {
  return String(value || '').trim().slice(0, maximumLength);
}

function numberValue(value, minimum = 0, maximum = Number.MAX_SAFE_INTEGER) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return 0;
  return Math.max(minimum, Math.min(maximum, parsed));
}

function dateMillis(value) {
  if (value && typeof value.toMillis === 'function') return value.toMillis();
  if (value && typeof value.toDate === 'function') return value.toDate().getTime();
  if (typeof value === 'number') return value;
  return typeof value === 'string' ? Date.parse(value) : Number.NaN;
}

function isoValue(...values) {
  for (const value of values) {
    const millis = dateMillis(value);
    if (Number.isFinite(millis)) return new Date(millis).toISOString();
  }
  return '';
}

function plainMap(value) {
  return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
}

function safeStringList(value, maximumItems = 100, maximumLength = 160) {
  return Array.isArray(value)
    ? value.slice(0, maximumItems)
      .map((item) => stringValue(item, maximumLength))
      .filter(Boolean)
    : [];
}

function safeCoordinate(value, capturedAtFields = []) {
  const raw = plainMap(value);
  const latitude = Number(raw.latitude);
  const longitude = Number(raw.longitude);
  if (
    !Number.isFinite(latitude) || latitude < -90 || latitude > 90
    || !Number.isFinite(longitude) || longitude < -180 || longitude > 180
  ) return null;
  const accuracyMeters = Number(raw.accuracyMeters ?? raw.accuracy);
  const altitudeMeters = Number(raw.altitudeMeters ?? raw.altitude);
  const capturedAtLocal = isoValue(
    ...capturedAtFields.map((field) => raw[field]),
    raw.capturedAtLocal,
    raw.recordedAtLocal,
    raw.pinnedAtLocal
  );
  return {
    latitude,
    longitude,
    ...(Number.isFinite(accuracyMeters) && accuracyMeters >= 0
      ? { accuracyMeters }
      : {}),
    ...(Number.isFinite(altitudeMeters) ? { altitudeMeters } : {}),
    ...(capturedAtLocal ? { capturedAtLocal } : {}),
  };
}

function summaryData(sessionId, session) {
  const raw = plainMap(session);
  const report = plainMap(raw.summaryReport);
  const trail = plainMap(raw.trail);
  const startedAtLocal = isoValue(
    report.startedAtLocal,
    raw.startedAtLocal,
    raw.startedAt
  );
  const endedAtLocal = isoValue(
    report.endedAtLocal,
    raw.endedAtLocal,
    raw.endedAt
  );
  const startedMillis = dateMillis(startedAtLocal);
  const endedMillis = dateMillis(endedAtLocal);
  const measuredDurationSeconds = Number.isFinite(startedMillis)
    && Number.isFinite(endedMillis)
    ? Math.max(0, Math.round((endedMillis - startedMillis) / 1000))
    : 0;
  const durationSeconds = Math.round(numberValue(
    report.durationSeconds || measuredDurationSeconds,
    0,
    30 * 24 * 60 * 60
  ));
  const teamBuddies = Array.isArray(raw.teamBuddies) ? raw.teamBuddies : [];
  return {
    sessionId: stringValue(sessionId, 200),
    trailId: stringValue(raw.trailId || trail.trailId, 200),
    trailName: stringValue(raw.trailName || trail.name || report.trailName || 'Trail', 160),
    location: [trail.area, trail.state, trail.country]
      .map((part) => stringValue(part, 160)).filter(Boolean).join(', '),
    difficulty: stringValue(trail.difficulty, 80),
    hikeType: stringValue(raw.hikeType, 20) === 'team' ? 'team' : 'solo',
    startedAtLocal,
    endedAtLocal,
    durationSeconds,
    distanceKm: numberValue(report.distanceKm ?? raw.distanceKm, 0, 5000),
    checkIns: Math.round(numberValue(report.checkIns ?? raw.checkIns, 0, 100000)),
    manualPins: Math.round(numberValue(report.manualPins ?? raw.manualPins, 0, 100000)),
    routePointCount: Math.round(numberValue(
      report.routePointCount ?? raw.routePointCount,
      0,
      1000000
    )),
    batteryStartPercent: Math.round(numberValue(report.batteryStartPercent, 0, 100)),
    batteryEndPercent: Math.round(numberValue(report.batteryEndPercent, 0, 100)),
    teamMemberCount: raw.hikeType === 'team' ? Math.max(1, teamBuddies.length + 1) : 1,
    coverImageUrl: stringValue(
      Array.isArray(trail.coverImageUrl)
        ? trail.coverImageUrl[0]
        : Array.isArray(trail.coverImageUrls)
          ? trail.coverImageUrls[0]
          : trail.coverImageUrl,
      2000
    ),
  };
}

function sanitizedCheckpoint(value) {
  const raw = plainMap(value);
  const coordinate = safeCoordinate(raw);
  if (!coordinate) return null;
  return {
    name: stringValue(raw.name || raw.label || 'Checkpoint', 160),
    order: Math.round(numberValue(raw.order, 0, 1000)),
    ...coordinate,
  };
}

function sanitizedBuddy(value) {
  const raw = plainMap(value);
  return {
    name: stringValue(raw.name || raw.username || raw.displayName || 'Hiker', 80),
    status: stringValue(raw.status, 40),
  };
}

function detailData({
  sessionId,
  session,
  capture,
  checkIns,
  locationPoints,
  rating,
  groupChatId = '',
  memberTracks = [],
}) {
  const raw = plainMap(session);
  const trail = plainMap(raw.trail);
  const report = plainMap(raw.summaryReport);
  const routeCapture = plainMap(capture);
  const summary = summaryData(sessionId, raw);
  const capturedRoute = Array.isArray(routeCapture.routePoints)
    ? routeCapture.routePoints.map((point) => safeCoordinate(point)).filter(Boolean)
    : [];
  const telemetry = (Array.isArray(locationPoints) ? locationPoints : [])
    .map((point) => {
      const coordinate = safeCoordinate(point, ['recordedAtLocal']);
      if (!coordinate) return null;
      return {
        ...coordinate,
        pointType: stringValue(point.pointType, 40),
        batteryLevel: Math.round(numberValue(point.batteryLevel, 0, 100)),
      };
    })
    .filter(Boolean)
    .sort((left, right) => String(left.capturedAtLocal || '')
      .localeCompare(String(right.capturedAtLocal || '')));
  const routePoints = capturedRoute.length > 0 ? capturedRoute : telemetry;
  const manualPins = (Array.isArray(routeCapture.manualPins)
    ? routeCapture.manualPins
    : [])
    .map((pin) => {
      const coordinate = safeCoordinate(plainMap(pin).coordinate);
      if (!coordinate) return null;
      return {
        pinId: stringValue(pin.pinId, 200),
        pinnedAtLocal: isoValue(pin.pinnedAtLocal),
        coordinate,
      };
    })
    .filter(Boolean);
  const sanitizedCheckIns = (Array.isArray(checkIns) ? checkIns : [])
    .map((item) => ({
      checkInId: stringValue(item.checkInId, 200),
      status: stringValue(item.status || 'safe', 40),
      checkedInAtLocal: isoValue(item.createdAtLocal, item.createdAt),
      batteryLevel: Math.round(numberValue(item.batteryLevel, 0, 100)),
      coordinate: safeCoordinate(item.location),
    }))
    .sort((left, right) => left.checkedInAtLocal.localeCompare(right.checkedInAtLocal));
  const checkpoints = (Array.isArray(raw.checkpoints)
    ? raw.checkpoints
    : Array.isArray(trail.checkpoints) ? trail.checkpoints : [])
    .map(sanitizedCheckpoint).filter(Boolean)
    .sort((left, right) => left.order - right.order);
  const altitudeSamples = telemetry
    .map((point) => Number(point.altitudeMeters))
    .filter(Number.isFinite);
  const batterySamples = telemetry
    .map((point) => Number(point.batteryLevel))
    .filter(Number.isFinite);
  const durationHours = Math.max(summary.durationSeconds / 3600, 0);
  const averageSpeedKmh = durationHours > 0 ? summary.distanceKm / durationHours : 0;
  const paceMinutesPerKm = summary.distanceKm > 0
    ? summary.durationSeconds / 60 / summary.distanceKm
    : 0;
  const teamBuddies = Array.isArray(raw.teamBuddies)
    ? raw.teamBuddies.map(sanitizedBuddy).slice(0, 50)
    : [];
  return {
    summary,
    plan: {
      startPointName: stringValue(raw.startPointName, 160),
      destinationName: stringValue(raw.destinationName, 160),
      plannedStartTimeLocal: isoValue(raw.plannedStartTimeLocal),
      estimatedArrivalTimeLocal: isoValue(
        raw.estimatedArrivalTimeLocal,
        raw.expectedArrivalTimeLocal
      ),
      estimatedReturnTimeLocal: isoValue(
        raw.estimatedReturnTimeLocal,
        raw.expectedReturnTimeLocal
      ),
      checkpoints,
    },
    trail: {
      area: stringValue(trail.area, 160),
      state: stringValue(trail.state, 160),
      country: stringValue(trail.country, 160),
      difficulty: stringValue(trail.difficulty, 80),
      plannedDistanceKm: numberValue(trail.distanceKm, 0, 5000),
      estimatedDurationMinutes: Math.round(numberValue(
        trail.estimatedDurationMinutes,
        0,
        43200
      )),
      elevationGainMeters: Math.round(numberValue(trail.elevationGainMeters, 0, 100000)),
      ratingAverage: numberValue(trail.ratingAverage, 0, 5),
      ratingCount: Math.round(numberValue(trail.ratingCount, 0, 10000000)),
      isVerifiedTrail: trail.isVerifiedTrail === true,
    },
    performance: {
      averageSpeedKmh,
      paceMinutesPerKm,
      storedRoutePointCount: routePoints.length,
      routePointsDownsampled: routeCapture.routePointsDownsampled === true,
      minAltitudeMeters: altitudeSamples.length ? Math.min(...altitudeSamples) : null,
      maxAltitudeMeters: altitudeSamples.length ? Math.max(...altitudeSamples) : null,
    },
    safety: {
      safetyCheckInIntervalSeconds: Math.round(numberValue(
        raw.safetyCheckInIntervalSeconds,
        0,
        86400
      )),
      locationRecordingIntervalSeconds: Math.round(numberValue(
        raw.locationRecordingIntervalSeconds,
        0,
        86400
      )),
      shareLiveLocation: raw.shareLiveLocation === true,
      fallDetectionEnabled: raw.fallDetectionEnabled === true,
      pathDeviationEnabled: raw.pathDeviationEnabled === true,
      offlinePhysicalAlertEnabled: raw.offlinePhysicalAlertEnabled === true,
      duressEnabled: raw.duressEnabled === true,
      pathDeviationAlertCount: Math.round(numberValue(raw.pathDeviationAlertCount, 0, 100000)),
      completedChecklistItems: safeStringList(raw.completedChecklistItems),
      checkIns: sanitizedCheckIns,
      manualPins,
    },
    battery: {
      startPercent: summary.batteryStartPercent,
      endPercent: summary.batteryEndPercent,
      usedPercent: Math.max(0, summary.batteryStartPercent - summary.batteryEndPercent),
      lowestRecordedPercent: batterySamples.length ? Math.min(...batterySamples) : null,
    },
    team: {
      hikeType: summary.hikeType,
      memberCount: summary.teamMemberCount,
      buddies: teamBuddies,
      memberTracks: (Array.isArray(memberTracks) ? memberTracks : [])
        .slice(0, 50)
        .map((member, index) => ({
          name: stringValue(member?.name || `Hiker ${index + 1}`, 80),
          isCurrentUser: member?.isCurrentUser === true,
          routePoints: (Array.isArray(member?.routePoints)
            ? member.routePoints : [])
            .map((point) => safeCoordinate(point))
            .filter(Boolean)
            .slice(0, 5000),
        }))
        .filter((member) => member.routePoints.length > 0),
    },
    routePoints,
    telemetryPointCount: telemetry.length,
    insights: safeStringList(report.insights, 20, 300),
    rating: rating && typeof rating === 'object'
      ? {
          stars: Math.round(numberValue(rating.rating, 0, 5)),
          comment: stringValue(rating.comment, 500),
        }
      : { stars: 0, comment: '' },
    source: {
      sourceUpcomingHikeId: stringValue(raw.sourceUpcomingHikeId, 200),
      teamHikeSessionId: stringValue(raw.teamHikeSessionId, 200),
      groupChatId: stringValue(groupChatId, 200),
      routeCaptureAvailable: Object.keys(routeCapture).length > 0,
      sessionId: summary.sessionId,
    },
  };
}

module.exports = { detailData, summaryData };
