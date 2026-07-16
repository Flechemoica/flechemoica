const UsersView = (() => {
  let unsubscribe = null;
  let firestore = null;
  let functions = null;
  let tableBody = null;
  let statusNode = null;
  let searchInput = null;
  let users = [];
  let authMetadata = new Map();
  let viewLoaded = false;
  let viewLoadPromise = null;
  let documentClickBound = false;

  function init() {
    resolveNodes();

    if (!documentClickBound) {
      document.addEventListener("click", closeOptionsMenus);
      documentClickBound = true;
    }
  }

  function resolveNodes() {
    tableBody = document.getElementById("users-table-body");
    statusNode = document.getElementById("users-status");
    searchInput = document.getElementById("users-search");

    if (searchInput && !searchInput.dataset.bound) {
      searchInput.addEventListener("input", () => renderUsers(filterUsers()));
      searchInput.dataset.bound = "true";
    }
  }

  async function ensureView() {
    if (viewLoaded) {
      resolveNodes();
      return;
    }

    if (!viewLoadPromise) {
      viewLoadPromise = loadView();
    }

    await viewLoadPromise;
    resolveNodes();
  }

  async function loadView() {
    const panel = document.getElementById("users-panel");
    if (!panel) throw new Error("Panneau utilisateurs introuvable.");

    const viewSrc = panel.dataset.viewSrc;
    if (viewSrc && !panel.innerHTML.trim()) {
      const response = await fetch(viewSrc, { cache: "no-store" });
      if (!response.ok) throw new Error("Vue utilisateurs introuvable.");
      panel.innerHTML = await response.text();
    }

    viewLoaded = true;
  }

  function setStatus(message, tone = "") {
    if (!statusNode) return;
    statusNode.textContent = message;
    statusNode.dataset.tone = tone;
  }

  async function start() {
    try {
      await ensureView();
      if (unsubscribe) return;

      const services = AuthGate.ensureFirebase();
      firestore = services.firestore;
      functions = firebase.functions ? firebase.app().functions("europe-west1") : null;

      if (!firestore) {
        setStatus("Firestore indisponible.", "error");
        return;
      }

      setStatus("Chargement...");
      unsubscribe = firestore
        .collection("users")
        .orderBy("createdAt", "desc")
        .onSnapshot(
          (snapshot) => {
            users = snapshot.docs;
            renderUsers(filterUsers());
            setStatus("");
            loadAuthMetadata(snapshot.docs);
          },
          (error) => {
            setStatus(error.message || "Impossible de charger les utilisateurs.", "error");
          }
        );
    } catch (error) {
      resolveNodes();
      setStatus(error.message || "Impossible de charger la page utilisateurs.", "error");
    }
  }

  function stop() {
    if (!unsubscribe) return;
    unsubscribe();
    unsubscribe = null;
  }

  function renderUsers(docs) {
    if (!tableBody) return;

    tableBody.replaceChildren();

    if (!docs.length) {
      const row = document.createElement("tr");
      const cell = document.createElement("td");
      cell.colSpan = 6;
      cell.className = "empty-cell";
      cell.textContent = "Aucun utilisateur.";
      row.append(cell);
      tableBody.append(row);
      return;
    }

    const fragment = document.createDocumentFragment();
    docs.forEach((doc) => fragment.append(createUserRow(doc.id, doc.data())));
    tableBody.append(fragment);
  }

  function filterUsers() {
    const query = normalizeSearch(searchInput?.value);
    if (!query) return users;

    return users.filter((doc) => {
      const data = doc.data();
      return [
        data.pseudo,
        data.displayName,
        data.email,
        data.emailKey,
      ].some((value) => normalizeSearch(value).includes(query));
    });
  }

  function normalizeSearch(value) {
    return String(value || "")
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .trim();
  }

  function createUserRow(id, data) {
    const row = document.createElement("tr");

    row.append(
      makeIdentityCell(id, data),
      makeEmailCell(data),
      makeProviderCell(id, data),
      makeStatusCell(data.status || data.role || "Utilisateur"),
      makeTextCell(formatValue(data.createdAt)),
      makeActionsCell(id, data)
    );

    return row;
  }

  function makeIdentityCell(id, data) {
    const cell = document.createElement("td");
    const name = document.createElement("strong");
    const meta = document.createElement("span");

    name.textContent = data.pseudo || data.displayName || data.email || "Utilisateur";
    meta.textContent = data.uid || id;

    cell.append(name, meta);
    return cell;
  }

  function makeTextCell(value) {
    const cell = document.createElement("td");
    cell.textContent = value == null || value === "" ? "-" : String(value);
    return cell;
  }

  function makeEmailCell(data) {
    const cell = document.createElement("td");
    const email = document.createElement("span");
    email.className = "email-value";
    email.textContent = data.email || data.emailKey || "-";
    cell.append(email);

    if (data.emailVerificationStatus === "pending") {
      const verification = document.createElement("span");
      verification.className = "email-pending";
      verification.textContent = "E-mail à confirmer";
      cell.append(verification);
    }

    if (data.accountStatus === "disabled") {
      const disabled = document.createElement("span");
      disabled.className = "email-pending";
      disabled.textContent = "Compte désactivé";
      cell.append(disabled);
    }

    return cell;
  }

  function makeStatusCell(value) {
    const cell = document.createElement("td");
    const badge = document.createElement("span");
    cell.className = "role-cell";
    badge.className = "status-badge";
    badge.textContent = value;
    cell.append(badge);
    return cell;
  }

  function makeProviderCell(id, data) {
    const cell = document.createElement("td");
    const badge = document.createElement("span");
    const metadata = authMetadata.get(data.uid || id);
    badge.className = "status-badge provider-badge";
    badge.textContent = formatProviders(metadata?.providers || getFallbackProviders(data));
    cell.append(badge);
    return cell;
  }

  function makeActionsCell(id, data) {
    const cell = document.createElement("td");
    const wrapper = document.createElement("div");
    const button = document.createElement("button");
    const menu = document.createElement("div");
    const isEditor = String(data.status || data.role || "").toLowerCase() === "editor";
    const isDisabled = data.accountStatus === "disabled";
    const currentUser = firebase.auth().currentUser;
    const isCurrentUser = currentUser && (id === currentUser.uid || data.uid === currentUser.uid);

    cell.className = "actions-cell";
    wrapper.className = "options-menu-wrap";

    button.className = "options-button";
    button.type = "button";
    button.textContent = "...";
    button.setAttribute("aria-label", `Options pour ${data.pseudo || data.email || "cet utilisateur"}`);
    button.setAttribute("aria-expanded", "false");
    button.addEventListener("click", (event) => {
      event.stopPropagation();
      toggleOptionsMenu(menu, button);
    });

    menu.className = "options-menu is-hidden";
    menu.setAttribute("role", "menu");

    menu.append(
      createMenuButton("Réinitialiser le mot de passe", () => resetPassword(id, data))
    );

    if (!isCurrentUser) {
      menu.append(
        createMenuButton(
          isDisabled ? "Réactiver le compte" : "Désactiver le compte",
          () => setAccountDisabled(id, data, !isDisabled)
        ),
        createMenuButton("Supprimer le compte", () => deleteAccount(id, data), "danger")
      );
    }

    if (!(isCurrentUser && isEditor)) {
      menu.append(
        createMenuButton(isEditor ? "Retirer statut Éditeur" : "Déclarer statut Éditeur", () => {
        if (isEditor) {
          removeEditorStatus(id, data);
        } else {
          promoteToEditor(id, data);
        }
        })
      );
    }

    wrapper.append(button, menu);
    cell.append(wrapper);
    return cell;
  }

  function createMenuButton(label, action, tone = "") {
    const menuButton = document.createElement("button");
    menuButton.type = "button";
    menuButton.setAttribute("role", "menuitem");
    menuButton.textContent = label;
    if (tone) menuButton.dataset.tone = tone;
    menuButton.addEventListener("click", (event) => {
      event.stopPropagation();
      closeOptionsMenus();
      action();
    });
    return menuButton;
  }

  function toggleOptionsMenu(menu, button) {
    const shouldOpen = menu.classList.contains("is-hidden");
    closeOptionsMenus();

    if (shouldOpen) {
      menu.classList.remove("is-hidden");
      button.setAttribute("aria-expanded", "true");
    }
  }

  function closeOptionsMenus() {
    document.querySelectorAll(".options-menu").forEach((menu) => {
      menu.classList.add("is-hidden");
    });

    document.querySelectorAll(".options-button[aria-expanded='true']").forEach((button) => {
      button.setAttribute("aria-expanded", "false");
    });
  }

  async function promoteToEditor(id, data) {
    const label = data.pseudo || data.email || "cet utilisateur";
    const shouldPromote = window.confirm(`Déclarer ${label} comme Éditeur et marquer son e-mail à confirmer ?`);
    if (!shouldPromote) return;

    try {
      setStatus("Mise à jour...");
      await firestore.collection("users").doc(id).update({
        status: "Editor",
        emailVerificationStatus: "pending",
        emailVerificationRequestedAt: firebase.firestore.FieldValue.serverTimestamp(),
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      });
      setStatus("Utilisateur passé en Editor. E-mail à confirmer.");
    } catch (error) {
      setStatus(error.message || "Impossible de mettre à jour l'utilisateur.", "error");
    }
  }

  async function loadAuthMetadata(docs) {
    if (!functions) return;

    const uids = docs
      .map((doc) => String(doc.data().uid || doc.id || "").trim())
      .filter(Boolean);

    if (!uids.length) return;

    try {
      const response = await functions.httpsCallable("adminUsersMeta")({ uids });
      authMetadata = new Map(
        (response.data?.users || []).map((user) => [user.uid, user])
      );
      renderUsers(filterUsers());
    } catch (error) {
      console.warn("Impossible de charger les métadonnées Auth.", error);
    }
  }

  function getFallbackProviders(data) {
    const rawProvider = data.providerId || data.signInProvider || data.provider || data.authProvider;
    if (Array.isArray(rawProvider)) return rawProvider;
    if (rawProvider) return [rawProvider];
    return data.email || data.emailKey ? ["password"] : [];
  }

  function formatProviders(providers) {
    const labels = [...new Set(providers.map(formatProvider).filter(Boolean))];
    return labels.length ? labels.join(", ") : "-";
  }

  function formatProvider(provider) {
    const normalized = String(provider || "").toLowerCase();

    if (normalized === "password" || normalized === "email" || normalized === "emailpassword") {
      return "E-mail";
    }

    if (normalized === "google.com" || normalized === "google") {
      return "Google";
    }

    if (normalized === "apple.com" || normalized === "apple") {
      return "Apple";
    }

    if (normalized === "phone" || normalized === "phone.com") {
      return "Téléphone";
    }

    return provider ? String(provider) : "";
  }

  async function resetPassword(id, data) {
    const email = String(data.email || data.emailKey || "").trim();
    if (!email) {
      setStatus("Aucune adresse e-mail disponible pour cet utilisateur.", "error");
      return;
    }

    const label = data.pseudo || email;
    const shouldReset = window.confirm(`Envoyer un e-mail de réinitialisation du mot de passe à ${label} ?`);
    if (!shouldReset) return;

    try {
      setStatus("Envoi de l'e-mail...");
      await firebase.auth().sendPasswordResetEmail(email);
      await firestore.collection("users").doc(id).update({
        passwordResetRequestedAt: firebase.firestore.FieldValue.serverTimestamp(),
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      });
      setStatus("E-mail de réinitialisation envoyé.");
    } catch (error) {
      setStatus(error.message || "Impossible d'envoyer l'e-mail de réinitialisation.", "error");
    }
  }

  async function setAccountDisabled(id, data, shouldDisable) {
    if (!functions) {
      setStatus("Cloud Functions indisponible.", "error");
      return;
    }

    const label = data.pseudo || data.email || "cet utilisateur";
    const message = shouldDisable
      ? `Désactiver le compte de ${label} ? Il ne pourra plus se connecter.`
      : `Réactiver le compte de ${label} ?`;
    if (!window.confirm(message)) return;

    try {
      setStatus(shouldDisable ? "Désactivation..." : "Réactivation...");
      await functions.httpsCallable("adminUserAction")({
        action: shouldDisable ? "disable" : "enable",
        targetDocId: id,
      });
      setStatus(shouldDisable ? "Compte désactivé." : "Compte réactivé.");
    } catch (error) {
      setStatus(error.message || "Impossible de mettre à jour le compte.", "error");
    }
  }

  async function deleteAccount(id, data) {
    if (!functions) {
      setStatus("Cloud Functions indisponible.", "error");
      return;
    }

    const label = data.pseudo || data.email || "cet utilisateur";
    const shouldDelete = window.confirm(`Supprimer définitivement le compte de ${label} ? Cette action supprimera aussi son accès Firebase Auth.`);
    if (!shouldDelete) return;

    try {
      setStatus("Suppression...");
      await functions.httpsCallable("adminUserAction")({
        action: "delete",
        targetDocId: id,
      });
      setStatus("Compte supprimé.");
    } catch (error) {
      setStatus(error.message || "Impossible de supprimer le compte.", "error");
    }
  }

  async function removeEditorStatus(id, data) {
    const label = data.pseudo || data.email || "cet utilisateur";
    const shouldRemove = window.confirm(`Retirer le statut Éditeur de ${label} ?`);
    if (!shouldRemove) return;

    try {
      setStatus("Mise à jour...");
      await firestore.collection("users").doc(id).update({
        status: "Utilisateur",
        emailVerificationStatus: firebase.firestore.FieldValue.delete(),
        emailVerificationRequestedAt: firebase.firestore.FieldValue.delete(),
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      });
      setStatus("Statut Éditeur retiré.");
    } catch (error) {
      setStatus(error.message || "Impossible de retirer le statut Éditeur.", "error");
    }
  }

  function formatValue(value) {
    if (value == null || value === "") return "-";

    if (typeof value.toDate === "function") {
      return value.toDate().toLocaleString("fr-FR", {
        dateStyle: "short",
        timeStyle: "short",
      });
    }

    if (Array.isArray(value)) {
      return value.length ? value.map(formatValue).join(", ") : "-";
    }

    if (typeof value === "object") {
      return JSON.stringify(value);
    }

    return String(value);
  }

  return {
    init,
    start,
    stop,
  };
})();
