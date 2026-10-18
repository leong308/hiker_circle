// Only the owning active hike's sharing preference and sample interval can change during recovery.
'use strict';

function activeHikeLocationSettingsPatch(existing, draft, ErrorType, {hasTerminalState = false} = {}) {
  if (hasTerminalState || existing?.status !== 'active') return {};
  const shareLiveLocation = draft?.shareLiveLocation;
  const locationRecordingIntervalSeconds = draft?.locationRecordingIntervalSeconds;
  if (typeof shareLiveLocation !== 'boolean'
      || !Number.isInteger(locationRecordingIntervalSeconds)
      || locationRecordingIntervalSeconds < 5
      || locationRecordingIntervalSeconds > 3600) {
    throw new ErrorType('invalid-argument', 'Choose a valid live location preference and update interval.');
  }
  const requested = {
    shareLiveLocation,
    locationRecordingIntervalSeconds,
    locationRecordingIntervalMinutes: Math.max(1, Math.round(locationRecordingIntervalSeconds / 60)),
  };
  return Object.fromEntries(Object.entries(requested).filter(([key, value]) => existing[key] !== value));
}

module.exports = {activeHikeLocationSettingsPatch};
