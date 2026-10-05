'use strict';
// Read-only unless --reconcile is supplied: invoke the existing worker once, never create a hike/job.
const {firebaseAccessToken, projectId} = require('./seed_malaysia_trails');
const {schedulerJobName} = require('../functions/active_hike_monitor_schedule');
async function main() {
  if (projectId !== 'hiker-circle') throw new Error('Unexpected project.');
  const token = await firebaseAccessToken();
  async function api(url, method = 'GET', body) {
    const response = await fetch(url, {method, headers: {
      Authorization: `Bearer ${token}`, 'Content-Type': 'application/json',
    }, ...(body ? {body: JSON.stringify(body)} : {}), signal: AbortSignal.timeout(30000)});
    if (!response.ok) throw new Error(`Upcoming scheduler inspection failed (HTTP ${response.status}).`);
    return response.json();
  }
  const name = schedulerJobName(projectId, 'processUpcomingHikeOperations');
  const jobUrl = `https://cloudscheduler.googleapis.com/v1/${name}`;
  const matches = [];
  for (const region of ['us-central1', 'asia-southeast1']) {
    const result = await api(`https://cloudscheduler.googleapis.com/v1/projects/${projectId}/locations/${region}/jobs?pageSize=500`);
    if (result.nextPageToken) throw new Error('Inventory requires pagination; cannot confirm singleton.');
    matches.push(...(result.jobs || []).filter(job => job.name.includes('firebase-schedule-processUpcomingHikeOperations-')
      || /processupcominghikeoperations/i.test(job.httpTarget?.uri || '')));
  }
  if (matches.length !== 1 || matches[0].name !== name) throw new Error('Unexpected job inventory; refusing invocation.');
  const functions = [];
  for (const [region, functionName] of [['us-central1', 'processUpcomingHikeOperations'],
    ['asia-southeast1', 'reconcileUpcomingHikeOperationsOnWrite']]) {
    const info = await api(`https://cloudfunctions.googleapis.com/v2/projects/${projectId}/locations/${region}/functions/${functionName}`);
    functions.push({name: functionName, state: info.state, runtime: info.buildConfig?.runtime,
      ...(info.eventTrigger ? {retry: info.eventTrigger.retryPolicy} : {
        maxInstances: info.serviceConfig?.maxInstanceCount, concurrency: info.serviceConfig?.maxInstanceRequestConcurrency})});
  }
  if (functions.some(f => f.state !== 'ACTIVE')) throw new Error('Affected function is not ready.');
  if (process.argv.includes('--reconcile')) {
    await api(jobUrl + ':run', 'POST');
    console.log('Invoked existing upcoming maintenance once. No hike or job was created.');
  }
  const deadline = Date.now() + (process.argv.includes('--reconcile') ? 55000 : 0);
  let result;
  do {
    const query = await api(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:runQuery`, 'POST', {
      structuredQuery: {from: [{collectionId: 'upcomingHikes'}],
        where: {fieldFilter: {field: {fieldPath: 'isDeleted'}, op: 'EQUAL', value: {booleanValue: false}}}, limit: 1},
    });
    if (query.some(entry => entry.error)) throw new Error('Upcoming membership query failed.');
    const hasUpcomingListing = query.some(entry => entry.document);
    const job = await api(jobUrl);
    result = {upcomingJobs: matches.length, hasUpcomingListing, jobState: job.state, schedule: job.schedule, functions};
    if (job.state === (hasUpcomingListing ? 'ENABLED' : 'PAUSED')) break;
    if (Date.now() < deadline) await new Promise(resolve => setTimeout(resolve, 2000));
  } while (Date.now() < deadline);
  console.log(JSON.stringify(result, null, 2));
  if (result.jobState !== (result.hasUpcomingListing ? 'ENABLED' : 'PAUSED')) throw new Error('Job did not converge; inspect runtime logs.');
}
if (require.main === module) main().catch(error => {console.error(error.message); process.exitCode = 1;});
