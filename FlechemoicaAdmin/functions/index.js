const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { FieldValue, getFirestore } = require("firebase-admin/firestore");

initializeApp();

const EDITOR_STATUSES = new Set(["admin", "editor", "editors"]);

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

async function assertEditor(uid) {
  const db = getFirestore();
  const snapshot = await db.collection("users").doc(uid).get();
  const status = snapshot.exists ? normalizeStatus(snapshot.get("status") || snapshot.get("role")) : "";

  if (!EDITOR_STATUSES.has(status)) {
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
