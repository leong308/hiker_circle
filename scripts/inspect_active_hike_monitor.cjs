'use strict';
// Read-only by default. --reconcile invokes the existing monitor once via Scheduler.
const {firebaseAccessToken, projectId} = require('./seed_malaysia_trails');
const {schedulerJobName} = require('../functions/active_hike_monitor_schedule');
async function main() {
  if (projectId !== 'hiker-circle') throw new Error('Unexpected project.');
  const token = await firebaseAccessToken();
  async function api(url, method = 'GET', body) {
    const response = await fetch(url, {method, headers: {
      Authorization: `Bearer ${token}`, 'Content-Type': 'application/json',
    }, ...(body ? {body: JSON.stringify(body)} : {}), signal: AbortSignal.timeout(30000)});
    if (!response.ok) throw new Error(`Monitor inspection failed (HTTP ${response.status}).`);
    return response.json();
  }
  const jobUrl = `https://cloudscheduler.googleapis.com/v1/${schedulerJobName(projectId)}`;
  const matches = [];
  for (const region of ['us-central1', 'asia-southeast1']) {
    const result = await api(`https://cloudscheduler.googleapis.com/v1/projects/${projectId}/locations/${region}/jobs?pageSize=500`);
    if (result.nextPageToken) throw new Error('Scheduler inventory needs pagination before singleton verification.');
    matches.push(...(result.jobs || []).filter(job => job.name.includes('firebase-schedule-monitorActiveHikes-')
      || /monitoractivehikes/i.test(job.httpTarget?.uri || '')));
  }
  if (matches.length !== 1 || matches[0].name !== schedulerJobName(projectId)) {
    throw new Error('Unexpected monitor job inventory; refusing to invoke.');
  }
  const functionNames = { 'us-central1': ['monitorActiveHikes'],
    'asia-southeast1': ['awardAchievementsForStartedHike', 'recordHikeTerminalStateAndAchievements', 'preserveDeletedHikeTerminalState']};
  const functions = [];
  for (const [region, names] of Object.entries(functionNames)) {
    for (const name of names) {
      const info = await api(`https://cloudfunctions.googleapis.com/v2/projects/${projectId}/locations/${region}/functions/${name}`);
      functions.push({name, state: info.state, runtime: info.buildConfig?.runtime,
        ...(name === 'monitorActiveHikes' ? {maxInstances: info.serviceConfig?.maxInstanceCount,
          concurrency: info.serviceConfig?.maxInstanceRequestConcurrency} : {retry: info.eventTrigger?.retryPolicy})});
    }
  }
  if (functions.some(f => f.state !== 'ACTIVE')) throw new Error('Affected function is not ready.');
  if (process.argv.includes('--reconcile')) {
    await api(jobUrl + ':run', 'POST');
    console.log('Invoked the existing monitor once to reconcile live state. No hike was created.');
  }
  const deadline = Date.now() + (process.argv.includes('--reconcile') ? 55000 : 0);
  let result;
  do {
    const query = await api(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:runQuery`, 'POST', {
      structuredQuery: {from: [{collectionId: 'hikeSessions'}],
        where: {fieldFilter: {field: {fieldPath: 'status'}, op: 'EQUAL', value: {stringValue: 'active'}}}, limit: 1},
    });
    if (query.some(entry => entry.error)) throw new Error('Active membership query failed.');
    const hasActiveHike = query.some(entry => entry.document);
    const job = await api(jobUrl);
    result = {monitorJobs: matches.length, hasActiveHike, jobState: job.state, schedule: job.schedule, functions};
    if (job.state === (hasActiveHike ? 'ENABLED' : 'PAUSED')) break;
    if (Date.now() < deadline) await new Promise(resolve => setTimeout(resolve, 2000));
  } while (Date.now() < deadline);
  console.log(JSON.stringify(result, null, 2));
  if (result.jobState !== (result.hasActiveHike ? 'ENABLED' : 'PAUSED')) {
    throw new Error('Scheduler state has not converged to live active hikes; inspect runtime logs.');
  }
}
if (require.main === module) main().catch(error => {console.error(error.message); process.exitCode = 1;});
