const EDITOR_STATUS = "editor";
const AuthGate = (() => {
  let auth;
  let firestore;

    function ensureFirebase() {
      if (!window.firebase || !firebase.apps.length) {
        throw new Error("Firebase n'est pas encore initialise.");
      }

      auth = auth || firebase.auth();

      if (!firestore && firebase.firestore) {
        firestore = firebase.firestore();
      }

      return { auth, firestore };
    }

  function normalizeAccessValue(value) {
    return String(value || "").trim().toLowerCase();
  }

  function isEditorProfile(profile) {
    const status = normalizeAccessValue(profile?.status);
    return Boolean(profile && status === EDITOR_STATUS);
  }

  function hasAccountingAccess(profile) {
    if (!profile) return false;

    return profile.accountingAccess === true;
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
