const EDITOR_STATUSES = new Set(["admin", "editor", "editors"]);
const AuthGate = (() => {
  let auth;
  let firestore;
  let database;

    function ensureFirebase() {
      if (!window.firebase || !firebase.apps.length) {
        throw new Error("Firebase n'est pas encore initialise.");
      }

      auth = auth || firebase.auth();

      if (!firestore && firebase.firestore) {
        firestore = firebase.firestore();
      }

      database = database || (firebase.database ? firebase.database() : null);

      return { auth, firestore, database };
    }

  function normalizeEmail(email) {
    return String(email || "").trim().toLowerCase();
  }

  function normalizeAccessValue(value) {
    return String(value || "").trim().toLowerCase();
  }

  function isEditorProfile(profile) {
    const status = normalizeAccessValue(profile?.status || profile?.role);
    return Boolean(profile && EDITOR_STATUSES.has(status));
  }

  function hasAccountingAccess(profile) {
    if (!profile) return false;

    return profile.accountingAccess === true;
  }

  async function getFirestoreUser(uid, email) {
    if (!firestore) return null;

    const byUid = await firestore.collection("users").doc(uid).get();
    if (byUid.exists) {
      return { id: byUid.id, source: "firestore", ...byUid.data() };
    }

    const normalizedEmail = normalizeEmail(email);
    if (!normalizedEmail) return null;

    const byEmail = await firestore
      .collection("users")
      .where("email", "==", normalizedEmail)
      .limit(1)
      .get();

    if (!byEmail.empty) {
      const doc = byEmail.docs[0];
      return { id: doc.id, source: "firestore", ...doc.data() };
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
    if (!normalizedEmail) return null;

    const byEmail = await database
      .ref("users")
      .orderByChild("email")
      .equalTo(normalizedEmail)
      .limitToFirst(1)
      .get();

    if (!byEmail.exists()) return null;

    let foundUser = null;
    byEmail.forEach((child) => {
      foundUser = { id: child.key, source: "database", ...child.val() };
      return true;
    });

    return foundUser;
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
      throw new Error("Accès non autorisé.");
    }

    if (profile.source === "firestore" && profile.id !== user.uid) {
      const editorValue = normalizeAccessValue(profile.status || profile.role);
      await firestore.collection("users").doc(user.uid).set({
        uid: user.uid,
        email: normalizeEmail(user.email),
        status: editorValue,
        role: editorValue,
        migratedEditorSource: profile.id,
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }

    if (profile.emailVerificationStatus === "pending" && !user.emailVerified) {
      await user.sendEmailVerification();
      await auth.signOut();
      throw new Error("E-mail de confirmation envoyé. Veuillez le valider avant d'accéder à l'administration.");
    }

    if (profile.emailVerificationStatus === "pending" && user.emailVerified && profile.source === "firestore") {
      await firestore.collection("users").doc(profile.id).update({
        emailVerificationStatus: "confirmed",
        emailVerifiedAt: firebase.firestore.FieldValue.serverTimestamp(),
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      });
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
    hasAccountingAccess,
    onEditorStateChanged,
    signIn,
    signOut
  };
})();
