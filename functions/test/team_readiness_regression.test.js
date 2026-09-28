'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const functionsSource = fs.readFileSync(
  path.join(__dirname, '..', 'index.js'),
  'utf8'
);
const homeSource = fs.readFileSync(
  path.join(
    __dirname,
    '..',
    '..',
    'lib',
    'home',
    'View',
    'hiker_home_page.dart'
  ),
  'utf8'
);
const repositorySource = fs.readFileSync(
  path.join(
    __dirname,
    '..',
    '..',
    'lib',
    'app',
    'Data',
    'hiker_circle_firebase_repository.dart'
  ),
  'utf8'
);

test('host readiness emits one participant event with FCM and WhatsApp delivery', () => {
  assert.match(functionsSource, /beginReadiness:\s*\[10,/);
  assert.match(
    functionsSource,
    /action === 'beginReadiness'[\s\S]*Only the host can start team preparation[\s\S]*!team\.readinessStartedAtLocal[\s\S]*type: 'team_hike_ready'/
  );
  assert.match(functionsSource, /allowedTypes[\s\S]*'team_hike_ready'/);
  assert.match(functionsSource, /hostOnlyTypes[\s\S]*'team_hike_ready'/);
  assert.match(
    functionsSource,
    /exports\.deliverTeamReadinessWhatsApp = onDocumentCreated/
  );

  const whatsAppStart = functionsSource.indexOf(
    'exports.deliverTeamReadinessWhatsApp ='
  );
  const whatsAppEnd = functionsSource.indexOf(
    'exports.recoverFcmOutboxDeliveries =',
    whatsAppStart
  );
  const whatsAppBlock = functionsSource.slice(whatsAppStart, whatsAppEnd);
  assert.match(whatsAppBlock, /Open HikerCircle/);
  assert.doesNotMatch(whatsAppBlock, /https?:\/\//);
});

test('participant app restores readiness state and deduplicates the launch screen', () => {
  assert.match(
    repositorySource,
    /watchTeamReadinessForParticipant[\s\S]*participantPhoneNumbers[\s\S]*arrayContains/
  );
  assert.match(repositorySource, /action:\s*'beginReadiness'/);
  assert.match(homeSource, /_listenForTeamReadiness\(\)/);
  assert.match(homeSource, /_presentedTeamReadinessKeys/);
  assert.match(homeSource, /_drainPendingTeamReadiness\(\)/);
  assert.match(
    homeSource,
    /beginTeamHikeReadiness[\s\S]*_TeamHikeLaunchPage/
  );
});
