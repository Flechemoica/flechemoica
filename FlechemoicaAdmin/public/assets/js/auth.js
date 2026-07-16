const EDITOR_STATUSES = new Set(["editor", "editors"]);

const AuthGate = (() => {
  let auth;
  let firestore;
  let database;

  function ensureFirebase() {
    if (!window.firebase || !firebase.apps.length) {
      throw new Error("Firebase n'est pas encore initialise.");
    }

    auth = auth || firebase.auth();
    firestore = firestore || (firebase.firestore ? firebase.firestore() : null);
    database = database || (firebase.database ? firebase.database() : null);
    return { auth, firestore, database };
  }

  function normalizeEmail(email) {
    return String(email || "").trim().toLowerCase();
  }

  function isEditorProfile(profile) {
    const status = String((profile && profile.status) || "").trim().toLowerCase();
    return EDITOR_STATUSES.has(status);
  }

  async function getFirestoreUser(uid, email) {
    if (!firestore) return null;

    const byUid = await firestore.collection("users").doc(uid).get();
    if (byUid.exists) {
      return { id: byUid.id, source: "firestore", ...byUid.data() };
    }

    const normalizedEmail = normalizeEmail(email);
    const emailCandidates = [...new Set([email, normalizedEmail].filter(Boolean))];
    if (!emailCandidates.length) return null;

    for (const emailCandidate of emailCandidates) {
      const byEmail = await firestore
        .collection("users")
        .where("email", "==", emailCandidate)
        .limit(1)
        .get();

      if (!byEmail.empty) {
        const doc = byEmail.docs[0];
        return { id: doc.id, source: "firestore", ...doc.data() };
      }
    }

    return null;
  }

  async function getRealtimeUser(uid, email) {
    if (!database) return null;

    const byUid = await database.ref(`users/${uid}`).get();
    if (byUid.exists()) {
      return { id: uid, source: "database", ...byUid.val() };
    }

    const normalizedEmail = normalizeEmail(email);
    const emailCandidates = [...new Set([email, normalizedEmail].filter(Boolean))];
    if (!emailCandidates.length) return null;

    for (const emailCandidate of emailCandidates) {
      const byEmail = await database
        .ref("users")
        .orderByChild("email")
        .equalTo(emailCandidate)
        .limitToFirst(1)
        .get();

      if (!byEmail.exists()) continue;

      let foundUser = null;
      byEmail.forEach((child) => {
        foundUser = { id: child.key, source: "database", ...child.val() };
        return true;
      });

      return foundUser;
    }

    return null;
  }

  async function getEditorProfile(user) {
    ensureFirebase();

    const firestoreUser = await getFirestoreUser(user.uid, user.email);
    if (firestoreUser) return firestoreUser;

    return getRealtimeUser(user.uid, user.email);
  }

  async function requireEditor(user) {
    const profile = await getEditorProfile(user);

    if (!isEditorProfile(profile)) {
      await auth.signOut();
      throw new Error("Ce compte n'a pas le statut Editor.");
    }

    return profile;
  }

  async function signIn(email, password) {
    ensureFirebase();
    const credentials = await auth.signInWithEmailAndPassword(email, password);
    const profile = await requireEditor(credentials.user);
    return { user: credentials.user, profile };
  }

  function onEditorStateChanged(callback) {
    ensureFirebase();

    return auth.onAuthStateChanged(async (user) => {
      if (!user) {
        callback({ user: null, profile: null, error: null });
        return;
      }

      try {
        const profile = await requireEditor(user);
        callback({ user, profile, error: null });
      } catch (error) {
        callback({ user: null, profile: null, error });
      }
    });
  }

  async function signOut() {
    ensureFirebase();
    await auth.signOut();
  }

  return {
    ensureFirebase,
    onEditorStateChanged,
    signIn,
    signOut,
  };
})();
