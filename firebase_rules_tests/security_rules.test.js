'use strict';

const fs = require('node:fs');
const path = require('node:path');
const firebase = require('firebase/compat/app');
require('firebase/compat/firestore');
const {FieldValue} = firebase.firestore;
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');

const PROJECT_ID = 'demo-hiker-circle';
const BUCKET = `gs://${PROJECT_ID}.appspot.com`;
const ROOT = path.resolve(__dirname, '..');

const OWNER_UID = 'user_owner';
const OWNER_PHONE = '+60111111111';
const MEMBER_UID = 'user_member';
const MEMBER_PHONE = '+60222222222';
const OUTSIDER_UID = 'user_outsider';
const OUTSIDER_PHONE = '+60333333333';
const ADMIN_UID = 'user_admin';
const ADMIN_PHONE = '+60444444444';

const tests = [];

function test(name, body) {
  tests.push({name, body});
}

function userContext(environment, uid, phoneNumber, extraClaims = {}) {
  return environment.authenticatedContext(uid, {phoneNumber, ...extraClaims});
}

function validPost({postId, authorId = OWNER_UID, phone = OWNER_PHONE}) {
  return {
    postId,
    authorId,
    authorPhoneNumber: phone,
    caption: 'A safe hike update',
    visibility: 'public',
    likeCount: 0,
    commentCount: 0,
    createdAtLocal: '2026-08-04T10:00:00.000Z',
  };
}

function validMessage(overrides = {}) {
  return {
    chatId: 'chat-1',
    senderPhone: OWNER_PHONE,
    senderName: 'Owner',
    text: 'Reached checkpoint one.',
    sentAtLocal: '2026-08-04T10:00:00.000Z',
    isSystemMessage: false,
    seenBy: [OWNER_PHONE],
    ...overrides,
  };
}

async function seedFirestore(environment) {
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const writes = [
      db.doc(`users/${OWNER_UID}`).set({
        phoneNumber: OWNER_PHONE,
        passwordHash: 'private-hash',
        sos_contacts: [],
        sosContactsCount: 0,
      }),
      db.doc(`users/${MEMBER_UID}`).set({phoneNumber: MEMBER_PHONE}),
      db.doc(`users/${OUTSIDER_UID}`).set({phoneNumber: OUTSIDER_PHONE}),
      db.doc(`users/${ADMIN_UID}`).set({phoneNumber: ADMIN_PHONE, isAdmin: true}),
      db.doc('teams/team-1').set({
        teamId: 'team-1',
        leaderId: OWNER_UID,
        memberIds: [OWNER_UID, MEMBER_UID],
      }),
      db.doc('teamHikeSessions/team-live-1').set({
        teamHikeSessionId: 'team-live-1',
        hostPhoneNumber: OWNER_PHONE,
        participantPhoneNumbers: [OWNER_PHONE, MEMBER_PHONE],
        phase: 'active',
      }),
      db.doc('upcomingHikes/upcoming-1').set({
        hikeId: 'upcoming-1',
        creatorPhone: OWNER_PHONE,
        participantPhones: [OWNER_PHONE, MEMBER_PHONE],
      }),
      db.doc('groupChats/chat-1').set({
        creatorPhone: OWNER_PHONE,
        participantPhones: [OWNER_PHONE, MEMBER_PHONE],
        participantNames: {60111111111: 'Owner', 60222222222: 'Member'},
        hikeSessionId: 'hike-1',
        chatType: 'group',
        createdAtLocal: '2026-08-04T10:00:00.000Z',
      }),
      db.doc('groupChats/chat-1/messages/seed-message').set(validMessage()),
      db.doc('communityPosts/public-post').set(validPost({postId: 'public-post'})),
      db.doc('communityPosts/private-post').set({
        ...validPost({postId: 'private-post'}),
        visibility: 'private',
      }),
      db.doc('checkIns/checkin-1').set({
        userId: OWNER_UID,
        userPhoneNumber: OWNER_PHONE,
        sessionId: 'hike-1',
      }),
      db.doc('hikeSessions/hike-1').set({
        sessionId: 'hike-1',
        userId: OWNER_UID,
        userPhoneNumber: OWNER_PHONE,
        status: 'active',
      }),
      db.doc('hikeSessions/hike-member').set({
        sessionId: 'hike-member',
        userId: MEMBER_UID,
        userPhoneNumber: MEMBER_PHONE,
        status: 'active',
      }),
      // Simulate documents written under the legacy rules by a different
      // signed-in account before deterministic ownership was enforced.
      db.doc('localLocationPoints/hike-1_99').set({
        sessionId: 'hike-member',
        userId: MEMBER_UID,
        userPhoneNumber: MEMBER_PHONE,
      }),
      db.doc('hikeRouteCaptures/hike-1').set({
        sessionId: 'hike-member',
        userId: MEMBER_UID,
        userPhoneNumber: MEMBER_PHONE,
      }),
      db.doc(`downloadedMaps/${OWNER_UID}_trail-legacy`).set({
        downloadedMapId: `${OWNER_UID}_trail-legacy`,
        userId: MEMBER_UID,
        userPhoneNumber: MEMBER_PHONE,
        trailId: 'trail-legacy',
      }),
      db.doc('sosAlerts/sos-1').set({
        userId: OWNER_UID,
        phoneNumber: OWNER_PHONE,
        status: 'queued',
      }),
      db.doc('whatsAppMessageLogs/log-1').set({
        userId: OWNER_UID,
        senderPhoneNumber: OWNER_PHONE,
        status: 'sent',
      }),
      db.doc('sosWhatsAppDispatches/dispatch-1').set({
        ownerUid: OWNER_UID,
        status: 'sent',
      }),
      db.doc('userAchievements/award-1').set({
        userId: OWNER_UID,
        achievementId: 'safe-hiker',
      }),
      db.doc('fcmOutbox/outbox-1').set({targetPhone: MEMBER_PHONE}),
      db.doc('teamHikeActionRateLimits/rate-1').set({count: 1}),
    ];
    await Promise.all(writes);
  });
}

async function run() {
  const environment = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(path.join(ROOT, 'firestore.rules'), 'utf8'),
    },
    storage: {
      rules: fs.readFileSync(path.join(ROOT, 'storage.rules'), 'utf8'),
    },
  });

  const owner = userContext(environment, OWNER_UID, OWNER_PHONE);
  const member = userContext(environment, MEMBER_UID, MEMBER_PHONE);
  const outsider = userContext(environment, OUTSIDER_UID, OUTSIDER_PHONE);
  const admin = userContext(environment, ADMIN_UID, ADMIN_PHONE, {isAdmin: true});
  const anonymous = environment.unauthenticatedContext();

  const ownerDb = owner.firestore();
  const memberDb = member.firestore();
  const outsiderDb = outsider.firestore();
  const adminDb = admin.firestore();
  const anonymousDb = anonymous.firestore();

  try {
    await seedFirestore(environment);

    test('private user records are self/admin only', async () => {
      await assertSucceeds(ownerDb.doc(`users/${OWNER_UID}`).get());
      await assertSucceeds(adminDb.doc(`users/${OWNER_UID}`).get());
      await assertFails(memberDb.doc(`users/${OWNER_UID}`).get());
      await assertFails(anonymousDb.doc(`users/${OWNER_UID}`).get());
    });

    test('canonical push token registration and revocation are atomic and owner-only', async () => {
      const reference = ownerDb.doc(`users/${OWNER_UID}`);
      await environment.withSecurityRulesDisabled(async context => {
        await context.firestore().doc(reference.path).update({
          fcmTokens: ['legacy-token'], activeFcmToken: 'legacy-token', lastFcmToken: 'legacy-token',
        });
      });
      await assertSucceeds(ownerDb.runTransaction(async transaction => {
        await transaction.get(reference);
        transaction.set(reference, {
          currentAppId: 'phone-1', activeFcmAppInstanceId: 'phone-1',
          fcmTokenByAppId: {'phone-1': 'current-device-token'}, fcmTokenSchemaVersion: 2,
          fcmTokens: FieldValue.delete(), activeFcmToken: FieldValue.delete(),
          lastFcmToken: FieldValue.delete(),
        }, {merge: true});
      }));
      const registered = (await reference.get()).data();
      if (registered.fcmTokenSchemaVersion !== 2 || registered.fcmTokens !== undefined
          || registered.activeFcmToken !== undefined || registered.lastFcmToken !== undefined) {
        throw new Error('Canonical registration did not remove redundant token aliases.');
      }
      await assertFails(outsiderDb.doc(reference.path).update({fcmTokenSchemaVersion: 2}));
      await assertSucceeds(ownerDb.runTransaction(async transaction => {
        await transaction.get(reference);
        transaction.update(reference, {
          'fcmTokenByAppId.phone-1': FieldValue.delete(), currentAppId: FieldValue.delete(),
          activeFcmAppInstanceId: FieldValue.delete(),
        });
      }));
      if (Object.keys((await reference.get()).data().fcmTokenByAppId).length) {
        throw new Error('Revoked device token remains registered.');
      }
    });

    test('historical forecast archives are backend-only while hike history stays readable', async () => {
      const archive = 'hikeSessions/hike-1/snapshotArchives/trailForecast';
      await environment.withSecurityRulesDisabled(async context => {
        await context.firestore().doc(archive).set({schemaVersion: 1, weather: {hourly: [1, 2]}});
      });
      await assertSucceeds(ownerDb.doc('hikeSessions/hike-1').get());
      await assertSucceeds(adminDb.doc('hikeSessions/hike-1').get());
      for (const db of [ownerDb, memberDb, adminDb, anonymousDb]) {
        await assertFails(db.doc(archive).get());
        await assertFails(db.doc(archive).set({schemaVersion: 2}));
        await assertFails(db.doc(archive).delete());
      }
    });

    test('community AI review queue and check status are administrator-read-only', async () => {
      const reviewPath = 'communityModerationReviews/test-review';
      const statusPath = 'communityModerationStatus/current';
      const internalPaths = ['communityModerationChecks/test-check', 'maintenanceState/communityModerationQuota',
        'maintenanceState/communityModerationModels', 'maintenanceState/communityModerationRun'];
      await environment.withSecurityRulesDisabled(async context => {
        for (const path of [reviewPath, statusPath, ...internalPaths]) await context.firestore().doc(path).set({status: 'pending'});
      });
      for (const path of [reviewPath, statusPath]) {
        await assertSucceeds(adminDb.doc(path).get());
        for (const db of [ownerDb, memberDb, outsiderDb, anonymousDb]) await assertFails(db.doc(path).get());
        for (const db of [ownerDb, adminDb, anonymousDb]) {
          await assertFails(db.doc(path).set({status: 'dismissed'}));
          await assertFails(db.doc(path).delete());
        }
      }
      for (const path of internalPaths) {
        await assertFails(adminDb.doc(path).get());
        await assertFails(ownerDb.doc(path).set({forged: true}));
      }
      await assertSucceeds(adminDb.collection('communityModerationReviews').where('status', '==', 'pending').limit(50).get());
      await assertFails(ownerDb.collection('communityModerationReviews').get());
    });

    test('assistant conversation and messages are account-private', async () => {
      const conversation = `assistantConversations/${OWNER_UID}`;
      const message = `${conversation}/messages/message-1`;
      await assertSucceeds(ownerDb.doc(conversation).set({clearedAtMicros: 10}));
      await assertSucceeds(ownerDb.doc(message).set({
        id: 'message-1', createdAtMicros: 11,
        payload: '{"text":"Find a trail","isUser":true}',
      }));
      await assertSucceeds(ownerDb.doc(message).get());
      await assertSucceeds(ownerDb.collection(`${conversation}/messages`).get());
      await assertSucceeds(ownerDb.collection(`${conversation}/messages`)
        .where('createdAtMicros', '<=', 11).limit(400).get());
      await assertFails(memberDb.doc(message).get());
      await assertFails(memberDb.collection(`${conversation}/messages`).get());
      await assertFails(adminDb.doc(message).get());
      await assertFails(anonymousDb.doc(message).get());
      await assertFails(memberDb.doc(message).set({
        id: 'message-1', createdAtMicros: 12, payload: '{}',
      }));
      await assertFails(ownerDb.doc(`${conversation}/messages/message-2`).set({
        id: 'wrong-id', createdAtMicros: 12, payload: '{}',
      }));
      await assertSucceeds(ownerDb.doc(message).delete());
    });

    test('user creation requires exact uid and phone identity', async () => {
      const self = userContext(environment, 'new_self', '+60555555555').firestore();
      await assertSucceeds(
        self.doc('users/new_self').set({phoneNumber: '+60555555555'}),
      );
      await assertFails(
        self.doc('users/not_new_self').set({phoneNumber: '+60555555555'}),
      );
      await assertFails(
        self.doc('users/new_self_wrong_phone').set({phoneNumber: '+60666666666'}),
      );
    });

    test('emergency contacts are bounded and structurally validated', async () => {
      const contacts = [
        {name: 'One', phoneNumber: '+60123456781', relationship: 'Friend'},
        {name: 'Two', phoneNumber: '+60123456782', relationship: 'Sibling'},
        {name: 'Three', phoneNumber: '+60123456783', relationship: 'Parent'},
      ];
      await assertSucceeds(
        ownerDb.doc(`users/${OWNER_UID}`).update({
          sos_contacts: contacts,
          sosContactsCount: contacts.length,
        }),
      );
      await assertFails(
        ownerDb.doc(`users/${OWNER_UID}`).update({
          sos_contacts: [...contacts, contacts[0]],
          sosContactsCount: 4,
        }),
      );
      await assertFails(
        ownerDb.doc(`users/${OWNER_UID}`).update({
          sos_contacts: [{...contacts[0], phoneNumber: 'not-e164'}],
          sosContactsCount: 1,
        }),
      );
      await assertFails(
        ownerDb.doc(`users/${OWNER_UID}`).update({
          sos_contacts: contacts,
          sosContactsCount: 2,
        }),
      );
    });

    test('custom SOS notes have fixed keys and bounded text', async () => {
      await assertSucceeds(
        ownerDb.doc(`users/${OWNER_UID}`).update({
          sosWhatsappNotes: {
            manual: 'Please contact emergency services.',
            duress: 'Do not call if that would increase risk.',
            medical: 'Medical help is required.',
          },
        }),
      );
      await assertFails(
        ownerDb.doc(`users/${OWNER_UID}`).update({
          sosWhatsappNotes: {arbitrary_mode: 'not allowed'},
        }),
      );
      await assertFails(
        ownerDb.doc(`users/${OWNER_UID}`).update({
          sosWhatsappNotes: {manual: 'x'.repeat(241)},
        }),
      );
      await assertFails(
        ownerDb.doc(`users/${OWNER_UID}`).update({sosWhatsappNotes: 'not-a-map'}),
      );
    });

    test('preferred SOS timezone is a bounded timezone identifier', async () => {
      await assertSucceeds(
        ownerDb.doc(`users/${OWNER_UID}`).update({
          preferredTimeZone: 'Asia/Singapore',
        }),
      );
      await assertSucceeds(
        ownerDb.doc(`users/${OWNER_UID}`).update({
          preferredTimeZone: 'America/New_York',
        }),
      );
      await assertFails(
        ownerDb.doc(`users/${OWNER_UID}`).update({
          preferredTimeZone: '../invalid timezone',
        }),
      );
      await assertFails(
        ownerDb.doc(`users/${OWNER_UID}`).update({
          preferredTimeZone: 'x'.repeat(81),
        }),
      );
      await assertFails(
        ownerDb.doc(`users/${OWNER_UID}`).update({preferredTimeZone: 8}),
      );
    });

    test('solo-hike records require exact self identity', async () => {
      await assertFails(
        ownerDb.doc('hikeSessions/client-created').set({
          sessionId: 'client-created',
          userId: OWNER_UID,
          userPhoneNumber: OWNER_PHONE,
          status: 'active',
        }),
      );
      await assertFails(
        ownerDb.doc('hikeSessions/hike-1').update({status: 'completed'}),
      );
      await assertSucceeds(
        ownerDb.doc('hikeSessions/hike-1').update({
          monitoringHeartbeatAtLocal: '2026-08-04T10:01:00.000Z',
          monitoringLifecycleState: 'resumed',
          monitoringExpected: true,
          monitoringFcmToken: 'owner-fcm-token',
          updatedAtLocal: '2026-08-04T10:01:00.000Z',
        }),
      );
      await assertSucceeds(
        ownerDb.doc('hikeSessions/hike-1').update({
          terminationSignalNonce: 'nonce-1',
          terminationSignalAtLocal: '2026-08-04T10:02:00.000Z',
          monitoringLifecycleState: 'detached',
          updatedAtLocal: '2026-08-04T10:02:00.000Z',
        }),
      );
      await assertSucceeds(
        ownerDb.doc('hikeSessions/hike-1').update({
          latestLocation: {latitude: 3.1, longitude: 101.7},
          latestLocationUpdatedAtLocal: '2026-08-04T10:03:00.000Z',
          updatedAtLocal: '2026-08-04T10:03:00.000Z',
        }),
      );
      await assertSucceeds(
        ownerDb.doc('hikeSessions/hike-1').update({
          lastPathDeviation: {distanceMeters: 125},
          lastPathDeviationAtLocal: '2026-08-04T10:04:00.000Z',
          pathDeviationAlertCount: 1,
        }),
      );
      await assertFails(
        ownerDb.doc('hikeSessions/hike-1').update({
          draft: {hikeType: 'team'},
        }),
      );
      await assertFails(
        ownerDb.doc('hikeSessions/hike-1').update({checkIns: 999}),
      );
      await assertFails(
        ownerDb.doc('hikeSessions/hike-1').update({
          userId: MEMBER_UID,
          userPhoneNumber: MEMBER_PHONE,
        }),
      );
      await assertFails(
        adminDb.doc('hikeSessions/hike-1').update({
          userId: ADMIN_UID,
          userPhoneNumber: ADMIN_PHONE,
        }),
      );
      await assertFails(
        adminDb.doc('hikeSessions/hike-1').update({trailName: 'Forged'}),
      );
      await assertFails(ownerDb.doc('hikeSessions/hike-1').delete());
      await assertFails(
        ownerDb.doc('checkIns/checkin-owner-new').set({
          userId: OWNER_UID,
          userPhoneNumber: OWNER_PHONE,
          sessionId: 'hike-1',
        }),
      );
      await assertFails(
        ownerDb.doc('checkIns/checkin-forged').set({
          userId: MEMBER_UID,
          userPhoneNumber: MEMBER_PHONE,
          sessionId: 'hike-1',
        }),
      );
      await assertFails(
        ownerDb.doc('checkIns/checkin-1').update({
          userId: MEMBER_UID,
          userPhoneNumber: MEMBER_PHONE,
        }),
      );
    });

    test('live links allow anonymous get, deny enumeration and require server activation', async () => {
      const expiry = new Date(Date.now() + 3600000);
      const row = { shareId: 'server-share', ownerUserId: OWNER_UID,
        phoneNumber: OWNER_PHONE, isActive: true, expiresAt: expiry,
        latestLocation: { latitude: 3.1, longitude: 101.7 } };
      await environment.withSecurityRulesDisabled(async context => {
        await context.firestore().doc('live_location_shares/server-share').set(row);
      });
      await assertSucceeds(anonymousDb.doc('live_location_shares/server-share').get());
      await assertFails(anonymousDb.collection('live_location_shares')
        .where('isActive', '==', true).where('expiresAt', '>', new Date()).get());
      await assertFails(outsiderDb.collection('live_location_shares')
        .where('isActive', '==', true).where('expiresAt', '>', new Date()).get());
      await assertSucceeds(ownerDb.collection('live_location_shares')
        .where('ownerUserId', '==', OWNER_UID).get());
      await assertFails(ownerDb.doc('live_location_shares/client-share').set({ ...row, shareId: 'client-share' }));
      await assertFails(ownerDb.doc('live_location_shares/server-share').update({ expiresAt: new Date(expiry.getTime() + 1) }));
      await assertSucceeds(ownerDb.doc('live_location_shares/server-share').update({ latestLocation: { latitude: 3.2, longitude: 101.8 } }));
      await assertSucceeds(ownerDb.doc('live_location_shares/server-share').update({ isActive: false }));
      await assertFails(anonymousDb.doc('live_location_shares/server-share').get());
      await assertFails(ownerDb.doc('live_location_shares/server-share').update({ isActive: true }));
      await assertSucceeds(ownerDb.doc('live_location_shares/server-share').get());
    });

    test('location samples are callable-only and canonical owner controls cleanup', async () => {
      await assertFails(
        memberDb.doc('localLocationPoints/hike-1_2').set({
          sessionId: 'hike-member',
          userId: MEMBER_UID,
          userPhoneNumber: MEMBER_PHONE,
          latitude: 3.1,
          longitude: 101.7,
        }),
      );
      await assertFails(
        ownerDb.doc('localLocationPoints/arbitrary-point').set({
          sessionId: 'hike-1',
          userId: OWNER_UID,
          userPhoneNumber: OWNER_PHONE,
          latitude: 3.1,
          longitude: 101.7,
        }),
      );
      await assertFails(
        ownerDb.doc('localLocationPoints/hike-1_2').set({
          sessionId: 'hike-1',
          userId: OWNER_UID,
          userPhoneNumber: OWNER_PHONE,
          latitude: 3.1,
          longitude: 101.7,
        }),
      );
      await assertFails(
        ownerDb.doc('localLocationPoints/hike-1_99').set({
          sessionId: 'hike-1',
          userId: OWNER_UID,
          userPhoneNumber: OWNER_PHONE,
          latitude: 3.2,
          longitude: 101.8,
        }),
      );
      await assertFails(ownerDb.doc('localLocationPoints/hike-1_99').delete());
      await environment.withSecurityRulesDisabled(async context => {
        await context.firestore().doc('localLocationPoints/hike-1_99').set({
          sessionId: 'hike-1', userId: OWNER_UID, userPhoneNumber: OWNER_PHONE,
          recordedAtMillis: 99, latitude: 3.2, longitude: 101.8,
        });
      });
      await assertFails(
        adminDb.doc('localLocationPoints/hike-1_99').delete(),
      );
      await assertFails(
        memberDb.doc('localLocationPoints/hike-1_99').delete(),
      );
      await assertSucceeds(
        ownerDb.doc('localLocationPoints/hike-1_99').delete(),
      );
    });

    test('downloaded maps bind document, account, and immutable trail identity', async () => {
      const mapId = `${OWNER_UID}_trail-1`;
      await assertFails(
        memberDb.doc(`downloadedMaps/${OWNER_UID}_trail-2`).set({
          downloadedMapId: `${OWNER_UID}_trail-2`,
          userId: MEMBER_UID,
          userPhoneNumber: MEMBER_PHONE,
          trailId: 'trail-2',
        }),
      );
      await assertFails(
        ownerDb.doc(`downloadedMaps/${OWNER_UID}_trail-1`).set({
          downloadedMapId: 'wrong-id',
          userId: OWNER_UID,
          userPhoneNumber: OWNER_PHONE,
          trailId: 'trail-1',
        }),
      );
      await assertSucceeds(
        ownerDb.doc(`downloadedMaps/${mapId}`).set({
          downloadedMapId: mapId,
          userId: OWNER_UID,
          userPhoneNumber: OWNER_PHONE,
          trailId: 'trail-1',
          trailName: 'Pine Trail',
        }),
      );
      await assertSucceeds(
        ownerDb.doc(`downloadedMaps/${mapId}`).update({
          trailName: 'Pine Trail Offline',
        }),
      );
      await assertFails(
        ownerDb.doc(`downloadedMaps/${mapId}`).update({trailId: 'trail-2'}),
      );
      await assertFails(
        ownerDb.doc(`downloadedMaps/${mapId}`).update({
          downloadedMapId: `${OWNER_UID}_trail-2`,
        }),
      );
      await assertFails(
        ownerDb.doc(`downloadedMaps/${mapId}`).update({
          userId: MEMBER_UID,
          userPhoneNumber: MEMBER_PHONE,
        }),
      );
      const legacyMapId = `${OWNER_UID}_trail-legacy`;
      await assertSucceeds(
        ownerDb.doc(`downloadedMaps/${legacyMapId}`).set({
          downloadedMapId: legacyMapId,
          userId: OWNER_UID,
          userPhoneNumber: OWNER_PHONE,
          trailId: 'trail-legacy',
          trailName: 'Recovered offline map',
        }, {merge: true}),
      );
    });

    test('route capture parent ownership defeats legacy preclaims', async () => {
      await assertFails(
        memberDb.doc('hikeRouteCaptures/hike-1').set({
          sessionId: 'hike-member',
          userId: MEMBER_UID,
          userPhoneNumber: MEMBER_PHONE,
          routePointCount: 1,
        }),
      );
      await assertFails(
        ownerDb.doc('hikeRouteCaptures/hike-1').set({
          sessionId: 'wrong-session',
          userId: OWNER_UID,
          userPhoneNumber: OWNER_PHONE,
        }),
      );
      await assertFails(
        ownerDb.doc('hikeRouteCaptures/missing-session').set({
          sessionId: 'missing-session',
          userId: OWNER_UID,
          userPhoneNumber: OWNER_PHONE,
        }),
      );
      await assertFails(
        ownerDb.doc('hikeRouteCaptures/hike-1').set({
          sessionId: 'hike-1',
          userId: MEMBER_UID,
          userPhoneNumber: MEMBER_PHONE,
        }),
      );
      await assertSucceeds(
        ownerDb.doc('hikeRouteCaptures/hike-1').set({
          sessionId: 'hike-1',
          userId: OWNER_UID,
          userPhoneNumber: OWNER_PHONE,
          routePointCount: 2,
        }),
      );
      await assertFails(adminDb.doc('hikeRouteCaptures/hike-1').delete());
      await assertFails(memberDb.doc('hikeRouteCaptures/hike-1').delete());
      await assertSucceeds(ownerDb.doc('hikeRouteCaptures/hike-1').delete());
    });

    test('team state and notification outbox are server-write only', async () => {
      await assertSucceeds(ownerDb.doc('teamHikeSessions/team-live-1').get());
      await assertSucceeds(memberDb.doc('teamHikeSessions/team-live-1').get());
      await assertFails(outsiderDb.doc('teamHikeSessions/team-live-1').get());
      await assertFails(
        ownerDb.doc('teamHikeSessions/team-live-1').update({phase: 'ended'}),
      );
      await assertFails(
        adminDb.doc('teamHikeSessions/team-live-1').update({phase: 'ended'}),
      );
      await assertFails(adminDb.doc('fcmOutbox/outbox-admin').set({targetPhone: OWNER_PHONE}));
      await assertFails(adminDb.doc('fcmOutbox/outbox-1').get());
      await assertFails(ownerDb.doc('teamHikeActionRateLimits/rate-1').get());
    });

    test('callable rate limits, receipts, and terminal state are server-only', async () => {
      const collections = [
        'upcomingHikeRateLimits',
        'directChatActionRateLimits',
        'activeHikeStartRateLimits',
        'hikeSessionRecoveryRateLimits',
        'buddyRequestRateLimits',
        'sosMessageRateLimits',
        'sosWhatsAppDispatches',
        'achievementEventReceipts',
        'communityCounterEventReceipts',
        'hikeSessionTerminalStates',
      ];
      for (const collection of collections) {
        await assertFails(ownerDb.doc(`${collection}/client`).get());
        await assertFails(ownerDb.doc(`${collection}/client`).set({forged: true}));
        await assertFails(adminDb.doc(`${collection}/admin`).set({forged: true}));
      }
    });

    test('scheduler controller and execution leases are backend-only', async () => {
      const paths = ['maintenanceState/activeHikeMonitorSchedule', 'maintenanceState/activeHikeMonitorRun',
        'maintenanceState/upcomingHikeOperationsSchedule', 'maintenanceState/upcomingHikeOperationsRun'];
      await environment.withSecurityRulesDisabled(async context => {
        for (const path of paths) await context.firestore().doc(path).set({leaseOwner: null, leaseExpiresAtMillis: 0});
      });
      for (const db of [ownerDb, memberDb, adminDb, anonymousDb]) {
        for (const path of paths) {
          await assertFails(db.doc(path).get());
          await assertFails(db.doc(path).set({leaseOwner: 'forged'}));
          await assertFails(db.doc(path).delete());
        }
      }
    });

    test('legacy team membership is readable but never client-mutated', async () => {
      await assertSucceeds(ownerDb.doc('teams/team-1').get());
      await assertSucceeds(memberDb.doc('teams/team-1').get());
      await assertFails(outsiderDb.doc('teams/team-1').get());
      await assertFails(ownerDb.doc('teams/team-1').update({memberIds: [OWNER_UID]}));
      await assertFails(adminDb.doc('teams/team-admin').set({memberIds: [ADMIN_UID]}));
    });

    test('upcoming hikes and group-chat creation are server-only', async () => {
      await assertSucceeds(ownerDb.doc('upcomingHikes/upcoming-1').get());
      await assertSucceeds(memberDb.doc('upcomingHikes/upcoming-1').get());
      await assertSucceeds(adminDb.doc('upcomingHikes/upcoming-1').get());
      await assertFails(outsiderDb.doc('upcomingHikes/upcoming-1').get());
      await assertFails(anonymousDb.doc('upcomingHikes/upcoming-1').get());
      await assertFails(ownerDb.doc('upcomingHikes/client-created').set({
        creatorPhone: OWNER_PHONE,
        participantPhones: [OWNER_PHONE],
      }));
      await assertFails(adminDb.doc('upcomingHikes/admin-created').set({
        creatorPhone: ADMIN_PHONE,
      }));
      await assertFails(ownerDb.doc('groupChats/client-chat').set({
        creatorPhone: OWNER_PHONE,
        participantPhones: [OWNER_PHONE],
        hikeSessionId: 'hike-client',
        chatType: 'group',
      }));
      await assertFails(adminDb.doc('groupChats/admin-chat').set({
        creatorPhone: ADMIN_PHONE,
        participantPhones: [ADMIN_PHONE],
      }));
      await assertFails(adminDb.doc('groupChats/chat-1').update({
        participantPhones: [ADMIN_PHONE],
      }));
      await assertFails(adminDb.doc('groupChats/chat-1').delete());
      await assertFails(ownerDb.doc('groupChats/chat-1').update({
        participantNames: {60111111111: 'Forged name'},
      }));
      await assertFails(ownerDb.doc('groupChats/chat-1').update({
        isDeleted: true,
        closureReason: 'forged',
      }));
    });

    test('production mobile queries satisfy the rule predicates', async () => {
      await assertSucceeds(
        ownerDb.collection('upcomingHikes')
          .where('creatorPhone', '==', OWNER_PHONE)
          .get(),
      );
      await assertSucceeds(
        ownerDb.collection('upcomingHikes')
          .where('participantPhones', 'array-contains', OWNER_PHONE)
          .get(),
      );
      await assertSucceeds(
        memberDb.collection('upcomingHikes')
          .where('participantPhones', 'array-contains', MEMBER_PHONE)
          .get(),
      );
      await assertFails(ownerDb.collection('upcomingHikes').get());
      await assertFails(outsiderDb.collection('upcomingHikes').get());
      await assertSucceeds(
        ownerDb.collection('groupChats')
          .where('participantPhones', 'array-contains', OWNER_PHONE)
          .orderBy('createdAtLocal', 'desc')
          .get(),
      );
      await assertFails(memberDb.collection('groupChats').get());
      await assertSucceeds(
        memberDb.collection('communityPosts')
          .where('visibility', '==', 'public')
          .orderBy('createdAtLocal', 'desc')
          .get(),
      );
      await assertFails(memberDb.collection('communityPosts').get());
      await assertSucceeds(
        ownerDb.collection('sosAlerts').where('userId', '==', OWNER_UID).get(),
      );
      await assertFails(memberDb.collection('sosAlerts').get());
    });

    test('chat membership and message sender identity are enforced', async () => {
      await assertSucceeds(ownerDb.doc('groupChats/chat-1').get());
      await assertSucceeds(memberDb.doc('groupChats/chat-1').get());
      await assertFails(outsiderDb.doc('groupChats/chat-1').get());
      await assertSucceeds(
        ownerDb.doc('groupChats/chat-1/messages/valid-owner').set(validMessage()),
      );
      await assertFails(
        ownerDb.doc('groupChats/chat-1/messages/forged-sender').set(
          validMessage({senderPhone: MEMBER_PHONE}),
        ),
      );
      await assertFails(
        ownerDb.doc('groupChats/chat-1/messages/forged-system').set(
          validMessage({isSystemMessage: true}),
        ),
      );
      await assertFails(
        ownerDb.doc('groupChats/chat-1/messages/forged-seen').set(
          validMessage({seenBy: [OWNER_PHONE, MEMBER_PHONE]}),
        ),
      );
      await assertFails(
        ownerDb.doc('groupChats/chat-1/messages/oversized-text').set(
          validMessage({text: 'x'.repeat(5001)}),
        ),
      );
      await assertFails(
        ownerDb.doc('groupChats/chat-1/messages/invalid-name').set(
          validMessage({senderName: 42}),
        ),
      );
      await assertFails(
        ownerDb.doc('groupChats/chat-1/messages/hidden-field').set({
          ...validMessage(),
          privileged: true,
        }),
      );
      await assertFails(
        ownerDb.doc('groupChats/chat-1/messages/external-attachment').set(
          validMessage({
            text: '',
            attachment: {
              type: 'document',
              url: 'https://evil.example/payload.pdf',
              fileName: 'payload.pdf',
              contentType: 'application/pdf',
              sizeBytes: 123,
            },
          }),
        ),
      );
      await assertSucceeds(
        ownerDb.doc('groupChats/chat-1/messages/valid-attachment').set(
          validMessage({
            text: '',
            attachment: {
              type: 'document',
              url: 'https://firebasestorage.googleapis.com/v0/b/'
                + 'hiker-circle.firebasestorage.app/o/'
                + 'group_chats%2Fchat-1%2Fattachments%2Freport.pdf?alt=media',
              fileName: 'report.pdf',
              contentType: 'application/pdf',
              sizeBytes: 123,
            },
          }),
        ),
      );
      await assertSucceeds(ownerDb.doc('groupChats/chat-1').update({
        lastMessage: 'Reached checkpoint one.',
        lastMessageAtLocal: '2026-08-04T10:00:00.000Z',
        lastMessageSenderPhone: OWNER_PHONE,
      }));
      await assertFails(ownerDb.doc('groupChats/chat-1').update({
        lastMessage: 'Forged member summary',
        lastMessageAtLocal: '2026-08-04T10:01:00.000Z',
        lastMessageSenderPhone: MEMBER_PHONE,
      }));
    });

    test('chat read-receipt maps only change the caller key', async () => {
      await assertSucceeds(ownerDb.doc('groupChats/chat-1').update({
        lastReadAt: {60111111111: '2026-08-04T10:00:00.000Z'},
        unreadCount: {60111111111: 0},
      }));
      await assertSucceeds(memberDb.doc('groupChats/chat-1').update({
        'lastReadAt.60222222222': '2026-08-04T10:01:00.000Z',
        'unreadCount.60222222222': 0,
      }));
      await assertFails(memberDb.doc('groupChats/chat-1').update({
        'lastReadAt.60111111111': '2026-08-04T10:02:00.000Z',
      }));
      await assertFails(memberDb.doc('groupChats/chat-1').update({
        'unreadCount.60111111111': 9,
      }));
    });

    test('seenBy updates only add the authenticated participant', async () => {
      const message = memberDb.doc('groupChats/chat-1/messages/seed-message');
      await assertSucceeds(message.update({seenBy: [OWNER_PHONE, MEMBER_PHONE]}));
      await assertFails(message.update({seenBy: [MEMBER_PHONE]}));
      await assertFails(
        message.update({seenBy: [OWNER_PHONE, MEMBER_PHONE, OUTSIDER_PHONE]}),
      );
      await assertFails(
        outsiderDb.doc('groupChats/chat-1/messages/seed-message').update({
          seenBy: [OWNER_PHONE, MEMBER_PHONE, OUTSIDER_PHONE],
        }),
      );
      await assertFails(message.update({text: 'rewritten'}));
    });

    test('community authors cannot forge moderation or aggregate counts', async () => {
      await assertSucceeds(
        ownerDb.doc('communityPosts/valid-new-post').set(
          validPost({postId: 'valid-new-post'}),
        ),
      );
      await assertFails(
        ownerDb.doc('communityPosts/moderated-at-create').set({
          ...validPost({postId: 'moderated-at-create'}),
          moderationStatus: 'approved',
        }),
      );
      await assertFails(
        ownerDb.doc('communityPosts/forged-count-at-create').set({
          ...validPost({postId: 'forged-count-at-create'}),
          commentCount: 500,
        }),
      );
      await assertSucceeds(
        ownerDb.doc('communityPosts/public-post').update({caption: 'Edited safely'}),
      );
      await assertFails(
        ownerDb.doc('communityPosts/public-post').update({moderationStatus: 'approved'}),
      );
      await assertFails(
        ownerDb.doc('communityPosts/public-post').update({commentCount: 999}),
      );
      await assertFails(
        adminDb.doc('communityPosts/public-post').update({commentCount: 1}),
      );
      await assertSucceeds(
        adminDb.doc('communityPosts/public-post').update({
          moderationStatus: 'approved',
          moderatedByAdminId: ADMIN_UID,
        }),
      );
    });

    test('comments require a public parent and exact author identity', async () => {
      await assertSucceeds(
        ownerDb.doc('communityPosts/public-post/comments/good-comment').set({
          commentId: 'good-comment',
          postId: 'public-post',
          authorId: OWNER_UID,
          authorPhoneNumber: OWNER_PHONE,
          body: 'Looks good.',
        }),
      );
      await assertFails(
        ownerDb.doc('communityPosts/private-post/comments/private-comment').set({
          commentId: 'private-comment',
          postId: 'private-post',
          authorId: OWNER_UID,
          authorPhoneNumber: OWNER_PHONE,
          body: 'Should not be accepted.',
        }),
      );
      await assertFails(
        ownerDb.doc('communityPosts/public-post/comments/forged-comment').set({
          commentId: 'forged-comment',
          postId: 'public-post',
          authorId: MEMBER_UID,
          authorPhoneNumber: MEMBER_PHONE,
          body: 'Forged.',
        }),
      );
      await assertFails(
        ownerDb.doc('communityPosts/public-post/comments/wrong-id').set({
          commentId: 'different-id',
          postId: 'public-post',
          authorId: OWNER_UID,
          authorPhoneNumber: OWNER_PHONE,
          body: 'Wrong path identity.',
        }),
      );
    });

    test('SOS alerts are private and provider dispatch logs are server-only', async () => {
      await assertSucceeds(ownerDb.doc('sosAlerts/sos-1').get());
      await assertSucceeds(adminDb.doc('sosAlerts/sos-1').get());
      await assertFails(memberDb.doc('sosAlerts/sos-1').get());
      await assertSucceeds(ownerDb.doc('sosAlerts/sos-owner-new').set({
        userId: OWNER_UID,
        phoneNumber: OWNER_PHONE,
        status: 'queued',
      }));
      await assertFails(ownerDb.doc('sosAlerts/sos-forged').set({
        userId: MEMBER_UID,
        phoneNumber: MEMBER_PHONE,
        status: 'queued',
      }));
      await assertFails(ownerDb.doc('sosAlerts/sos-1').update({
        userId: MEMBER_UID,
        phoneNumber: MEMBER_PHONE,
      }));
      await assertFails(adminDb.doc('sosAlerts/sos-1').delete());
      await assertFails(ownerDb.doc('whatsAppMessageLogs/log-1').get());
      await assertSucceeds(adminDb.doc('whatsAppMessageLogs/log-1').get());
      await assertFails(memberDb.doc('whatsAppMessageLogs/log-1').get());
      await assertFails(ownerDb.doc('sosWhatsAppDispatches/dispatch-1').get());
      await assertSucceeds(adminDb.doc('sosWhatsAppDispatches/dispatch-1').get());
      await assertFails(ownerDb.doc('whatsAppMessageLogs/log-forged').set({
        userId: MEMBER_UID,
        senderPhoneNumber: MEMBER_PHONE,
      }));
    });

    test('achievement awards cannot be forged by any mobile account', async () => {
      await assertSucceeds(ownerDb.doc('userAchievements/award-1').get());
      await assertFails(memberDb.doc('userAchievements/award-1').get());
      await assertFails(ownerDb.doc('userAchievements/forged').set({
        userId: OWNER_UID,
        achievementId: 'everything',
      }));
      await assertFails(adminDb.doc('userAchievements/admin-forged').set({
        userId: ADMIN_UID,
        achievementId: 'everything',
      }));
    });

    test('hazard creation binds reporter identity and unverified status', async () => {
      await assertSucceeds(ownerDb.doc('hazardReports/hazard-valid').set({
        hazardId: 'hazard-valid',
        reportedBy: OWNER_UID,
        reportedByPhoneNumber: OWNER_PHONE,
        status: 'unverified',
      }));
      await assertFails(ownerDb.doc('hazardReports/hazard-forged-user').set({
        hazardId: 'hazard-forged-user',
        reportedBy: MEMBER_UID,
        reportedByPhoneNumber: MEMBER_PHONE,
        status: 'unverified',
      }));
      await assertFails(ownerDb.doc('hazardReports/hazard-preapproved').set({
        hazardId: 'hazard-preapproved',
        reportedBy: OWNER_UID,
        reportedByPhoneNumber: OWNER_PHONE,
        status: 'verified',
      }));
      await assertFails(ownerDb.doc('hazardReports/hazard-pre-reviewed').set({
        hazardId: 'hazard-pre-reviewed',
        reportedBy: OWNER_UID,
        reportedByPhoneNumber: OWNER_PHONE,
        status: 'unverified',
        reviewedByAdminId: ADMIN_UID,
      }));
    });

    const ownerStorage = owner.storage(BUCKET);
    const memberStorage = member.storage(BUCKET);
    const outsiderStorage = outsider.storage(BUCKET);
    const adminStorage = admin.storage(BUCKET);

    const upload = (storage, objectPath, bytes, contentType, senderPhone) =>
      storage.ref(objectPath).put(bytes, {
        contentType,
        customMetadata: senderPhone ? {senderPhone} : undefined,
      });

    test('chat attachment upload enforces membership, sender, MIME, extension, and size', async () => {
      await assertSucceeds(
        upload(
          ownerStorage,
          'group_chats/chat-1/attachments/valid.jpg',
          new Uint8Array([0xff, 0xd8, 0xff]),
          'image/jpeg',
          OWNER_PHONE,
        ),
      );
      await assertSucceeds(
        upload(
          ownerStorage,
          'group_chats/chat-1/attachments/UPPERCASE.PDF',
          new Uint8Array([1]),
          'application/pdf',
          OWNER_PHONE,
        ),
      );
      await assertFails(
        upload(
          outsiderStorage,
          'group_chats/chat-1/attachments/outsider.jpg',
          new Uint8Array([1]),
          'image/jpeg',
          OUTSIDER_PHONE,
        ),
      );
      await assertFails(
        upload(
          ownerStorage,
          'group_chats/chat-1/attachments/forged-sender.jpg',
          new Uint8Array([1]),
          'image/jpeg',
          MEMBER_PHONE,
        ),
      );
      await assertFails(
        upload(
          ownerStorage,
          'group_chats/chat-1/attachments/mismatch.png',
          new Uint8Array([1]),
          'image/jpeg',
          OWNER_PHONE,
        ),
      );
      await assertFails(
        upload(
          ownerStorage,
          'group_chats/chat-1/attachments/blocked.svg',
          new Uint8Array([1]),
          'image/svg+xml',
          OWNER_PHONE,
        ),
      );
      await assertFails(
        upload(
          ownerStorage,
          'group_chats/chat-1/attachments/too-large.pdf',
          new Uint8Array(25 * 1024 * 1024 + 1),
          'application/pdf',
          OWNER_PHONE,
        ),
      );
      await assertFails(
        upload(
          ownerStorage,
          'group_chats/chat-1/attachments/valid.jpg',
          new Uint8Array([2]),
          'image/jpeg',
          OWNER_PHONE,
        ),
      );
    });

    test('attachment reads and deletes honor membership and uploader/admin ownership', async () => {
      const adminDeletePath = 'group_chats/chat-1/attachments/admin-delete.pdf';
      await assertSucceeds(
        upload(
          ownerStorage,
          adminDeletePath,
          new Uint8Array([1, 2, 3]),
          'application/pdf',
          OWNER_PHONE,
        ),
      );
      await assertSucceeds(memberStorage.ref(adminDeletePath).getMetadata());
      await assertFails(outsiderStorage.ref(adminDeletePath).getMetadata());
      await assertFails(memberStorage.ref(adminDeletePath).delete());
      await assertSucceeds(adminStorage.ref(adminDeletePath).delete());

      const ownerDeletePath = 'group_chats/chat-1/attachments/owner-delete.txt';
      await assertSucceeds(
        upload(
          ownerStorage,
          ownerDeletePath,
          new Uint8Array([1]),
          'text/plain',
          OWNER_PHONE,
        ),
      );
      await assertSucceeds(ownerStorage.ref(ownerDeletePath).delete());
    });

    test('profile photos are owner-only and restricted to supported images', async () => {
      await assertSucceeds(
        upload(
          ownerStorage,
          `profile_photos/${OWNER_UID}/avatar.png`,
          new Uint8Array([0x89, 0x50, 0x4e, 0x47]),
          'image/png',
        ),
      );
      await assertFails(
        upload(
          memberStorage,
          `profile_photos/${OWNER_UID}/member.png`,
          new Uint8Array([1]),
          'image/png',
        ),
      );
      await assertFails(
        upload(
          ownerStorage,
          `profile_photos/${OWNER_UID}/avatar.svg`,
          new Uint8Array([1]),
          'image/svg+xml',
        ),
      );
      await assertFails(
        upload(
          ownerStorage,
          `profile_photos/${OWNER_UID}/huge.jpg`,
          new Uint8Array(10 * 1024 * 1024 + 1),
          'image/jpeg',
        ),
      );
    });

    test('trail covers require admin and safe image metadata', async () => {
      await assertFails(
        upload(
          ownerStorage,
          'trail_covers/trail-1/owner.jpg',
          new Uint8Array([1]),
          'image/jpeg',
        ),
      );
      await assertSucceeds(
        upload(
          adminStorage,
          'trail_covers/trail-1/admin.jpg',
          new Uint8Array([0xff, 0xd8, 0xff]),
          'image/jpeg',
        ),
      );
      await assertFails(
        upload(
          adminStorage,
          'trail_covers/trail-1/admin.svg',
          new Uint8Array([1]),
          'image/svg+xml',
        ),
      );
      await assertSucceeds(adminStorage.ref('trail_covers/trail-1/admin.jpg').delete());
    });

    let failures = 0;
    for (const current of tests) {
      try {
        await current.body();
        console.log(`PASS ${current.name}`);
      } catch (error) {
        failures += 1;
        console.error(`FAIL ${current.name}`);
        console.error(error && error.stack ? error.stack : error);
      }
    }
    if (failures > 0) {
      throw new Error(`${failures} Firebase security-rule test(s) failed.`);
    }
    console.log(`PASS ${tests.length} Firebase security-rule groups`);
  } finally {
    await environment.cleanup();
  }
}

run().catch((error) => {
  console.error(error && error.stack ? error.stack : error);
  process.exitCode = 1;
});
