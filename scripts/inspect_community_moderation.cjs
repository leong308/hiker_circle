'use strict';
// Read-only by default. --run invokes the existing local-rule maintenance.
const {firebaseAccessToken, projectId} = require('./seed_malaysia_trails');
async function main() {
  if (projectId !== 'hiker-circle') throw new Error('Unexpected project.');
  const token = await firebaseAccessToken();
  async function api(url, method = 'GET') {
    const response = await fetch(url, {method, headers: {Authorization: `Bearer ${token}`}, signal: AbortSignal.timeout(30000)});
    if (!response.ok) throw new Error(`Inspection HTTP ${response.status}`);
    return response.json();
  }
  const name = 'checkCommunityContentIntegrity';
  const resource = `projects/${projectId}/locations/us-central1`;
  const functions = [];
  for (const entry of [name, 'reviewCommunityContentFlag']) {
    const f = await api(`https://cloudfunctions.googleapis.com/v2/${resource}/functions/${entry}`);
    functions.push({name: entry, state: f.state, runtime: f.buildConfig?.runtime,
      maxInstances: f.serviceConfig?.maxInstanceCount, concurrency: f.serviceConfig?.maxInstanceRequestConcurrency});
  }
  const jobs = await api(`https://cloudscheduler.googleapis.com/v1/${resource}/jobs?pageSize=500`);
  if (jobs.nextPageToken) throw new Error('Inventory requires pagination.');
  const matches = (jobs.jobs || []).filter(j => j.name.includes('firebase-schedule-checkCommunityContentIntegrity-'));
  if (matches.length !== 1 || functions.some(f => f.state !== 'ACTIVE')) throw new Error('Deployment is not ready.');
  if (process.argv.includes('--run')) {
    await api(`https://cloudscheduler.googleapis.com/v1/${matches[0].name}:run`, 'POST');
    console.log('Requested one execution of the existing community integrity job. No fake post created.');
  }
  console.log(JSON.stringify({schedulerJobs: matches.length, schedule: matches[0].schedule, state: matches[0].state, functions}, null, 2));
}
if (require.main === module) main().catch(error => {console.error(String(error.message).slice(0, 120)); process.exitCode = 1;});
