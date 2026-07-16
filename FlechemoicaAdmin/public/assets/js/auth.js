const EDITOR_STATUSES = new Set(["admin", "editor", "editors"]);

const AuthGate = (() => {
  let auth;
  let firestore;

  function ensureFirebase() {
    if (!window.firebase || !firebase.apps.length) {
      throw new Error("Firebase n'est pas encore initialise.");
    }

    auth = auth || firebase.auth();
    firestore = firestore || (firebase.firestore ? firebase.firestore() : null);
    return { auth, firestore };
  }

  function isEditorProfile(profile) {
    const status = String((profile && profile.status) || "").trim().toLowerCase();
    return EDITOR_STATUSES.has(status);
  }

  async function getFirestoreUser(uid) {
    if (!firestore) return null;

    const byUid = await firestore.collection("users").doc(uid).get();
    if (byUid.exists) {
      return { id: byUid.id, source: "firestore", ...byUid.data() };
    }

    return null;
  }

  async function getEditorProfile(user) {
    ensureFirebase();
    return getFirestoreUser(user.uid);
  }

  async function requireEditor(user) {
    const profile = await getEditorProfile(user);

    if (!isEditorProfile(profile)) {
      await auth.signOut();
      throw new Error("Accès non autorisé.");
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
