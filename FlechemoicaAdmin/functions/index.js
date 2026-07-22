const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { FieldValue, Timestamp, getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

const EDITOR_STATUS = "editor";
const APP_NOTIFICATION_TITLE = "Flèche-moi ça";
const WEEKLY_GRIDS_TOPIC = "weekly_grids";
const ALL_USERS_TOPIC = "all_users";
const MULTICAST_BATCH_SIZE = 500;
const GRIDS_COLLECTION = "grids";
const WEEKLY_GRID_TYPE = "WeeklyGrid";
const NOTIFICATION_LOGS_COLLECTION = "notificationLogs";
const EXPIRATION_UNIT_SECONDS = {
  minutes: 60,
  hours: 60 * 60,
  days: 24 * 60 * 60,
  weeks: 7 * 24 * 60 * 60,
};

function normalizeStatus(value) {
  return String(value || "").trim().toLowerCase();
}

function requireString(value, fieldName) {
  const normalized = String(value || "").trim();
  if (!normalized) {
    throw new HttpsError("invalid-argument", `${fieldName} est requis.`);
  }
  return normalized;
}

function normalizeNotificationOptions(data = {}) {
  const sound = String(data.sound || "disabled") === "default" ? "default" : "disabled";
  const badge = String(data.badge || "disabled") === "1" ? 1 : null;
  const expiration = data.expiration || {};
  const expirationValue = Number.parseInt(String(expiration.value || "1"), 10);
  const expirationUnit = String(expiration.unit || "days");
  const unitSeconds = EXPIRATION_UNIT_SECONDS[expirationUnit] || EXPIRATION_UNIT_SECONDS.weeks;
  const safeExpirationValue = Number.isFinite(expirationValue)
    ? Math.min(Math.max(expirationValue, 0), 365)
    : 1;

  return {
    sound,
    badge,
    expirationValue: safeExpirationValue,
    expirationUnit: EXPIRATION_UNIT_SECONDS[expirationUnit] ? expirationUnit : "weeks",
    expirationSeconds: safeExpirationValue * unitSeconds,
  };
}

function buildApnsConfig(options = {}) {
  const aps = {};

  if (options.sound === "default") {
    aps.sound = "default";
  }

  if (Number.isInteger(options.badge)) {
    aps.badge = options.badge;
  }

  const apns = {
    payload: { aps },
  };

  if (Number.isFinite(options.expirationSeconds) && options.expirationSeconds > 0) {
    apns.headers = {
      "apns-expiration": String(Math.floor(Date.now() / 1000) + options.expirationSeconds),
    };
  } else {
    apns.headers = {
      "apns-expiration": "0",
    };
  }

  return apns;
}

function chunkArray(items, size) {
  const chunks = [];
  for (let index = 0; index < items.length; index += size) {
    chunks.push(items.slice(index, index + size));
  }
  return chunks;
}

async function getRegisteredFCMTokens() {
  const snapshot = await getFirestore().collection("users").get();
  const tokens = new Set();

  snapshot.docs.forEach((doc) => {
    const fcmTokens = doc.get("fcmTokens");
    if (!Array.isArray(fcmTokens)) return;

    fcmTokens.forEach((token) => {
      const normalized = String(token || "").trim();
      if (normalized) tokens.add(normalized);
    });
  });

  return [...tokens];
}

async function assertEditor(uid) {
  const db = getFirestore();
  const snapshot = await db.collection("users").doc(uid).get();
  const status = snapshot.exists ? normalizeStatus(snapshot.get("status")) : "";

  if (status !== EDITOR_STATUS) {
    throw new HttpsError("permission-denied", "Accès non autorisé.");
  }
}

async function getTargetUser(targetDocId) {
  const db = getFirestore();
  const userRef = db.collection("users").doc(targetDocId);
  const snapshot = await userRef.get();
  const data = snapshot.exists ? snapshot.data() : {};
  const uid = String(data.uid || targetDocId).trim();

  if (!uid) {
    throw new HttpsError("invalid-argument", "Utilisateur introuvable.");
  }

  return { userRef, uid };
}

async function sendWeeklyGridNotification(gridID, gridData) {
  const messageID = await getMessaging().send({
    topic: WEEKLY_GRIDS_TOPIC,
    notification: {
      title: APP_NOTIFICATION_TITLE,
      body: "La grille de la semaine est disponible !",
    },
    data: {
      type: "weekly_grid_published",
      gridID,
      collection: GRIDS_COLLECTION,
      gridType: WEEKLY_GRID_TYPE,
      route: `weekly-grid/${gridID}`,
    },
    apns: {
      payload: {
        aps: {
          sound: "default",
        },
      },
    },
  });

  await getFirestore().collection(NOTIFICATION_LOGS_COLLECTION).add({
    kind: "weekly_grid",
    target: "topic",
    topic: WEEKLY_GRIDS_TOPIC,
    title: APP_NOTIFICATION_TITLE,
    body: "La grille de la semaine est disponible !",
    gridID,
    gridType: WEEKLY_GRID_TYPE,
    status: "sent",
    fcmMessageID: messageID,
    sentAt: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
  });
}

async function sendTopicNotification({ title, body, topic, data = {}, options = {} }) {
  return getMessaging().send({
    topic,
    notification: { title, body },
    data,
    apns: buildApnsConfig(options),
  });
}

async function sendAllUsersNotification({ title, body, data = {}, options = {} }) {
  const tokens = await getRegisteredFCMTokens();
  if (!tokens.length) {
    throw new Error("Aucun token FCM enregistré.");
  }

  const batches = chunkArray(tokens, MULTICAST_BATCH_SIZE);
  const results = await Promise.all(
    batches.map((batch) => getMessaging().sendEachForMulticast({
      tokens: batch,
      notification: { title, body },
      data,
      apns: buildApnsConfig(options),
    }))
  );

  return results.reduce(
    (summary, result) => ({
      tokenCount: summary.tokenCount,
      successCount: summary.successCount + result.successCount,
      failureCount: summary.failureCount + result.failureCount,
    }),
    {
      tokenCount: tokens.length,
      successCount: 0,
      failureCount: 0,
    }
  );
}

async function sendScheduledAdminNotifications() {
  const db = getFirestore();
  const now = Timestamp.now();
  const snapshot = await db
    .collection(NOTIFICATION_LOGS_COLLECTION)
    .where("status", "==", "scheduled")
    .limit(100)
    .get();

  const dueDocs = snapshot.docs.filter((doc) => {
    const scheduledAt = doc.get("scheduledAt");
    return scheduledAt && scheduledAt.toMillis && scheduledAt.toMillis() <= now.toMillis();
  });

  await Promise.all(dueDocs.map(async (doc) => {
    const data = doc.data();
    try {
      const delivery = await sendAllUsersNotification({
        title: APP_NOTIFICATION_TITLE,
        body: String(data.body || ""),
        data: {
          type: "admin_notification",
          notificationID: doc.id,
        },
        options: normalizeNotificationOptions(data),
      });

      await doc.ref.set({
        status: "sent",
        delivery,
        sentAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    } catch (error) {
      await doc.ref.set({
        status: "failed",
        errorMessage: error.message || "Erreur inconnue",
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }
  }));
}

async function publishDueGrids(collectionName) {
  const db = getFirestore();
  const now = Timestamp.now();
  const snapshot = await db
    .collection(collectionName)
    .where("status", "==", "scheduled")
    .limit(500)
    .get();

  if (snapshot.empty) return 0;

  const batch = db.batch();
  const dueDocs = snapshot.docs.filter((doc) => {
    const releaseAt = doc.get("releaseAt");
    return releaseAt && releaseAt.toMillis && releaseAt.toMillis() <= now.toMillis();
  });

  if (!dueDocs.length) return 0;

  dueDocs.forEach((doc) => {
    batch.update(doc.ref, {
      status: "published",
      publishedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  await batch.commit();
  return dueDocs.length;
}

exports.adminUserAction = onCall({ region: "europe-west1" }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Connexion requise.");
  }

  await assertEditor(request.auth.uid);

  const action = requireString(request.data?.action, "Action");
  const targetDocId = requireString(request.data?.targetDocId, "Utilisateur");
  const { userRef, uid } = await getTargetUser(targetDocId);

  if (uid === request.auth.uid) {
    throw new HttpsError("failed-precondition", "Cette action est bloquée sur votre propre compte.");
  }

  const auth = getAuth();
  const now = FieldValue.serverTimestamp();

  if (action === "disable") {
    await auth.updateUser(uid, { disabled: true });
    await userRef.set({
      accountStatus: "disabled",
      disabledAt: now,
      disabledBy: request.auth.uid,
      updatedAt: now,
    }, { merge: true });
    return { ok: true };
  }

  if (action === "enable") {
    await auth.updateUser(uid, { disabled: false });
    await userRef.set({
      accountStatus: "active",
      reenabledAt: now,
      reenabledBy: request.auth.uid,
      disabledAt: FieldValue.delete(),
      disabledBy: FieldValue.delete(),
      updatedAt: now,
    }, { merge: true });
    return { ok: true };
  }

  if (action === "delete") {
    try {
      await auth.deleteUser(uid);
    } catch (error) {
      if (error.code !== "auth/user-not-found") {
        throw error;
      }
    }

    await userRef.delete();
    return { ok: true };
  }

  throw new HttpsError("invalid-argument", "Action inconnue.");
});

exports.adminUsersMeta = onCall({ region: "europe-west1" }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Connexion requise.");
  }

  await assertEditor(request.auth.uid);

  const uids = Array.isArray(request.data?.uids)
    ? request.data.uids.map((uid) => String(uid || "").trim()).filter(Boolean)
    : [];

  if (!uids.length) {
    return { users: [] };
  }

  const identifiers = [...new Set(uids)].slice(0, 100).map((uid) => ({ uid }));
  const result = await getAuth().getUsers(identifiers);

  return {
    users: result.users.map((user) => ({
      uid: user.uid,
      disabled: user.disabled,
      providers: user.providerData.map((provider) => provider.providerId),
    })),
  };
});

exports.sendAdminNotification = onCall({ region: "europe-west1" }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Connexion requise.");
  }

  await assertEditor(request.auth.uid);

  const title = APP_NOTIFICATION_TITLE;
  const body = requireString(request.data?.body, "Texte").slice(0, 240);
  const scheduledAtValue = String(request.data?.scheduledAt || "").trim();
  const notificationOptions = normalizeNotificationOptions(request.data || {});
  const db = getFirestore();
  const now = Timestamp.now();
  const logRef = db.collection(NOTIFICATION_LOGS_COLLECTION).doc();

  const baseLog = {
    kind: "admin_manual",
    target: "topic",
    topic: ALL_USERS_TOPIC,
    title,
    body,
    sound: notificationOptions.sound,
    badge: notificationOptions.badge || "disabled",
    expirationValue: notificationOptions.expirationValue,
    expirationUnit: notificationOptions.expirationUnit,
    expirationSeconds: notificationOptions.expirationSeconds,
    createdBy: request.auth.uid,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };

  if (scheduledAtValue) {
    const scheduledDate = new Date(scheduledAtValue);
    if (!Number.isFinite(scheduledDate.getTime())) {
      throw new HttpsError("invalid-argument", "Date de programmation invalide.");
    }

    const scheduledAt = Timestamp.fromDate(scheduledDate);
    if (scheduledAt.toMillis() > now.toMillis()) {
      await logRef.set({
        ...baseLog,
        status: "scheduled",
        scheduledAt,
      });
      return { ok: true, notificationID: logRef.id, status: "scheduled" };
    }
  }

  try {
    const delivery = await sendAllUsersNotification({
      title,
      body,
      data: {
        type: "admin_notification",
        notificationID: logRef.id,
      },
      options: notificationOptions,
    });

    await logRef.set({
      ...baseLog,
      status: "sent",
      delivery,
      sentAt: FieldValue.serverTimestamp(),
    });

    return { ok: true, notificationID: logRef.id, status: "sent", delivery };
  } catch (error) {
    await logRef.set({
      ...baseLog,
      status: "failed",
      errorMessage: error.message || "Erreur inconnue",
    });
    throw new HttpsError("internal", error.message || "Impossible d'envoyer la notification.");
  }
});

exports.cancelAdminNotification = onCall({ region: "europe-west1" }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Connexion requise.");
  }

  await assertEditor(request.auth.uid);

  const notificationID = requireString(request.data?.notificationID, "Notification");
  const db = getFirestore();
  const ref = db.collection(NOTIFICATION_LOGS_COLLECTION).doc(notificationID);
  const snapshot = await ref.get();

  if (!snapshot.exists) {
    throw new HttpsError("not-found", "Notification introuvable.");
  }

  if (snapshot.get("status") !== "scheduled") {
    throw new HttpsError("failed-precondition", "Seules les notifications programmées peuvent être annulées.");
  }

  await ref.set({
    status: "cancelled",
    cancelledAt: FieldValue.serverTimestamp(),
    cancelledBy: request.auth.uid,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  return { ok: true, notificationID, status: "cancelled" };
});

exports.publishScheduledGrids = onSchedule(
  {
    region: "europe-west1",
    schedule: "0 17 * * *",
    timeZone: "Europe/Paris",
  },
  async () => {
    await Promise.all([
      publishDueGrids(GRIDS_COLLECTION),
      sendScheduledAdminNotifications(),
    ]);
  }
);

exports.notifyWeeklyGridPublished = onDocumentUpdated(
  {
    region: "europe-west1",
    document: `${GRIDS_COLLECTION}/{gridID}`,
  },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();

    if (!before || !after) return;
    if (normalizeStatus(before.status) === "published") return;
    if (normalizeStatus(after.status) !== "published") return;
    if (after.type !== WEEKLY_GRID_TYPE) return;

    await sendWeeklyGridNotification(event.params.gridID, after);
    await event.data.after.ref.set({
      notificationSentAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  }
);
