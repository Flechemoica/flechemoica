const UsersView = (() => {
  let unsubscribe = null;
  let firestore = null;
  let functions = null;
  let tableBody = null;
  let statusNode = null;
  let searchInput = null;
  let detailTitle = null;
  let detailMeta = null;
  let detailStatus = null;
  let accountDetails = null;
  let detailActions = null;
  let adStatsDetails = null;
  let playedGridsBody = null;
  let completedGridsBody = null;
  let unlockedGridsBody = null;
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
    detailTitle = document.getElementById("user-detail-title");
    detailMeta = document.getElementById("user-detail-meta");
    detailStatus = document.getElementById("user-detail-status");
    accountDetails = document.getElementById("user-account-details");
    detailActions = document.getElementById("user-detail-actions");
    adStatsDetails = document.getElementById("user-ad-stats");
    playedGridsBody = document.getElementById("user-played-grids");
    completedGridsBody = document.getElementById("user-completed-grids");
    unlockedGridsBody = document.getElementById("user-unlocked-grids");

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
    setDetailStatus(message, tone);
  }

  function setDetailStatus(message, tone = "") {
    if (!detailStatus) return;
    detailStatus.textContent = message;
    detailStatus.dataset.tone = tone;
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

  async function startDetail(userID) {
    try {
      await ensureDetailView();
      await renderUserDetail(userID);
    } catch (error) {
      resolveNodes();
      setDetailStatus(error.message || "Impossible de charger la fiche utilisateur.", "error");
    }
  }

  function renderUsers(docs) {
    if (!tableBody) return;

    tableBody.replaceChildren();

    if (!docs.length) {
      const row = document.createElement("tr");
      const cell = document.createElement("td");
      cell.colSpan = 7;
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
    const currentUser = firebase.auth().currentUser;
    const isCurrentUser = currentUser && (id === currentUser.uid || data.uid === currentUser.uid);

    if (isCurrentUser) {
      row.className = "current-user-row";
    }

    row.append(
      makeIdentityCell(id, data),
      makeEmailCell(data),
      makeProviderCell(id, data),
      makeStatusCell(data.status || data.role || "Utilisateur"),
      makeTextCell(formatValue(data.lastAppLaunchAt)),
      makeTextCell(formatValue(data.createdAt)),
      makeActionsCell(id, data)
    );

    return row;
  }

  function makeIdentityCell(id, data) {
    const cell = document.createElement("td");
    const name = document.createElement("a");
    const meta = document.createElement("span");

    name.className = "table-link";
    name.href = `/user/${encodeURIComponent(id)}.html`;
    name.textContent = data.pseudo || data.displayName || data.email || "Utilisateur";
    name.addEventListener("click", (event) => {
      event.preventDefault();
      window.history.pushState({ panelID: "user-detail-panel", userID: id }, "", name.href);
      DashboardView.showUserDetail(id);
    });
    meta.textContent = data.uid || id;

    cell.append(name, meta);
    return cell;
  }

  async function ensureDetailView() {
    const panel = document.getElementById("user-detail-panel");
    if (!panel) throw new Error("Panneau fiche utilisateur introuvable.");

    const viewSrc = panel.dataset.viewSrc;
    if (viewSrc && !panel.innerHTML.trim()) {
      const response = await fetch(viewSrc, { cache: "no-store" });
      if (!response.ok) throw new Error("Vue fiche utilisateur introuvable.");
      panel.innerHTML = await response.text();
    }

    resolveNodes();
  }

  async function renderUserDetail(userID) {
    const services = AuthGate.ensureFirebase();
    firestore = firestore || services.firestore;
    functions = functions || (firebase.functions ? firebase.app().functions("europe-west1") : null);

    let doc = users.find((entry) => entry.id === userID || entry.data().uid === userID);

    if (!doc && firestore && userID) {
      const snapshot = await firestore.collection("users").doc(userID).get();
      if (snapshot.exists) doc = snapshot;
    }

    const data = doc ? doc.data() : null;
    if (!data) throw new Error("Utilisateur introuvable.");

    const title = data?.pseudo || data?.displayName || data?.email || "Utilisateur";
    const id = doc.id;

    if (detailTitle) detailTitle.textContent = title;
    if (detailMeta) detailMeta.textContent = `ID : ${data.uid || id}`;
    setDetailStatus("");

    await renderAccountDetails(id, data);
    renderDetailActions(id, data);
    renderAdStats(data.adStats);
    await renderGridActivity(data);
  }

  function renderAdStats(adStats) {
    if (!adStatsDetails) return;

    const stats = getObject(adStats);
    const details = [
      ["Impressions totales", stats.totalImpressions || 0],
      ["Clics totaux", stats.totalClicks || 0],
      ["Impressions natives", stats.nativeImpressions || 0],
      ["Clics natives", stats.nativeClicks || 0],
      ["Impressions rewarded", stats.rewardedImpressions || 0],
      ["Clics rewarded", stats.rewardedClicks || 0],
    ];

    adStatsDetails.replaceChildren(...details.flatMap(([label, value]) => {
      const term = document.createElement("dt");
      const description = document.createElement("dd");
      term.textContent = label;
      description.textContent = value;
      return [term, description];
    }));
  }

  async function renderAccountDetails(id, data) {
    if (!accountDetails) return;

    const metadata = authMetadata.get(data.uid || id) || await loadSingleAuthMetadata(data.uid || id);
    const details = [
      ["Nom d'utilisateur", data.pseudo || data.displayName || "-"],
      ["E-mail", data.email || data.emailKey || "-"],
      ["Connexion", formatProviders(metadata?.providers || getFallbackProviders(data))],
      ["Rôle", data.status || data.role || "Utilisateur"],
      ["Dernier lancement", formatValue(data.lastAppLaunchAt)],
      ["Création", formatValue(data.createdAt)],
      ["Mise à jour", formatValue(data.updatedAt)],
      ["Statut du compte", data.accountStatus === "disabled" ? "Désactivé" : "Actif"],
    ];

    accountDetails.replaceChildren(...details.flatMap(([label, value]) => {
      const term = document.createElement("dt");
      const description = document.createElement("dd");
      term.textContent = label;
      description.textContent = value;
      return [term, description];
    }));
  }

  async function loadSingleAuthMetadata(uid) {
    if (!functions || !uid) return null;

    try {
      const response = await functions.httpsCallable("adminUsersMeta")({ uids: [uid] });
      const user = response.data?.users?.[0] || null;
      if (user) authMetadata.set(uid, user);
      return user;
    } catch {
      return null;
    }
  }

  function renderDetailActions(id, data) {
    if (!detailActions) return;

    const isEditor = String(data.status || data.role || "").toLowerCase() === "editor";
    const isDisabled = data.accountStatus === "disabled";
    const currentUser = firebase.auth().currentUser;
    const isCurrentUser = currentUser && (id === currentUser.uid || data.uid === currentUser.uid);

    detailActions.replaceChildren(
      makeDetailActionButton("Réinitialiser le mot de passe", () => resetPassword(id, data))
    );

    if (!isCurrentUser) {
      detailActions.append(
        makeDetailActionButton(
          isDisabled ? "Réactiver le compte" : "Désactiver le compte",
          () => setAccountDisabled(id, data, !isDisabled)
        ),
        makeDetailActionButton("Supprimer le compte", () => deleteAccount(id, data), "danger")
      );
    }

    if (!(isCurrentUser && isEditor)) {
      detailActions.append(
        makeDetailActionButton(isEditor ? "Retirer statut Éditeur" : "Déclarer statut Éditeur", () => {
          if (isEditor) {
            removeEditorStatus(id, data);
          } else {
            promoteToEditor(id, data);
          }
        })
      );
    }
  }

  function makeDetailActionButton(label, action, tone = "") {
    const button = document.createElement("button");
    button.type = "button";
    button.className = tone === "danger" ? "ghost-button detail-danger-button" : "ghost-button";
    button.textContent = label;
    button.addEventListener("click", action);
    return button;
  }

  async function renderGridActivity(data) {
    const gridNames = await loadGridNames([
      ...Object.keys(getObject(data.gridTimers)),
      ...Object.values(getObject(data.completedGrids)).map((entry) => entry?.gridId),
      ...getArray(data.unlockedGridIDs),
    ]);

    renderPlayedGrids(data.gridTimers, gridNames);
    renderCompletedGrids(data.completedGrids, gridNames);
    renderUnlockedGrids(data.unlockedGridIDs, gridNames);
  }

  function renderPlayedGrids(gridTimers, gridNames) {
    const timers = Object.entries(getObject(gridTimers))
      .sort(([leftID], [rightID]) => getGridName(leftID, gridNames).localeCompare(getGridName(rightID, gridNames)));

    renderRows(playedGridsBody, timers, 2, ([gridID, seconds]) => [
      getGridName(gridID, gridNames),
      formatDuration(seconds),
    ]);
  }

  function renderCompletedGrids(completedGrids, gridNames) {
    const entries = Object.values(getObject(completedGrids))
      .filter((entry) => entry && typeof entry === "object")
      .sort((left, right) => getTimestampMillis(right.completedAt) - getTimestampMillis(left.completedAt));

    renderRows(completedGridsBody, entries, 3, (entry) => [
      entry.title || getGridName(entry.gridId, gridNames),
      formatValue(entry.completedAt),
      formatDuration(entry.elapsedSeconds),
    ]);
  }

  function renderUnlockedGrids(unlockedGridIDs, gridNames) {
    const ids = getArray(unlockedGridIDs);
    renderRows(unlockedGridsBody, ids, 2, (gridID) => [
      getGridName(gridID, gridNames),
      gridID,
    ]);
  }

  function renderRows(body, items, colSpan, mapCells) {
    if (!body) return;
    body.replaceChildren();

    if (!items.length) {
      const row = document.createElement("tr");
      const cell = document.createElement("td");
      cell.colSpan = colSpan;
      cell.className = "empty-cell";
      cell.textContent = "Aucune donnée.";
      row.append(cell);
      body.append(row);
      return;
    }

    const fragment = document.createDocumentFragment();
    items.forEach((item) => {
      const row = document.createElement("tr");
      mapCells(item).forEach((value) => {
        const cell = document.createElement("td");
        cell.textContent = value == null || value === "" ? "-" : String(value);
        row.append(cell);
      });
      fragment.append(row);
    });
    body.append(fragment);
  }

  async function loadGridNames(ids) {
    const uniqueIDs = [...new Set(ids.map((id) => String(id || "").trim()).filter(Boolean))];
    const names = new Map();

    await Promise.all(uniqueIDs.map(async (gridID) => {
      try {
        const snapshot = await firestore.collection("grids").doc(gridID).get();
        if (!snapshot.exists) return;
        const data = snapshot.data();
        names.set(gridID, data.title || data.name || gridID);
      } catch {
        return;
      }
    }));

    return names;
  }

  function getGridName(gridID, gridNames) {
    return gridNames.get(String(gridID || "")) || String(gridID || "-");
  }

  function getObject(value) {
    return value && typeof value === "object" && !Array.isArray(value) ? value : {};
  }

  function getArray(value) {
    return Array.isArray(value) ? value : [];
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
    const normalized = String(value || "").toLowerCase();
    cell.className = "role-cell";
    badge.className = "status-badge";
    if (normalized === "editor") {
      badge.classList.add("status-badge-editor");
    } else if (normalized === "utilisateur") {
      badge.classList.add("status-badge-user");
    }
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
    const shouldPromote = await confirmSensitiveAction(
      `Déclarer ${label} comme Éditeur et marquer son e-mail à confirmer ?`
    );
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
    const shouldContinue = shouldDisable
      ? await confirmSensitiveAction(message)
      : window.confirm(message);
    if (!shouldContinue) return;

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
    const shouldDelete = await confirmSensitiveAction(
      `Supprimer définitivement le compte de ${label} ? Cette action supprimera aussi son accès Firebase Auth.`
    );
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
    const shouldRemove = await confirmSensitiveAction(`Retirer le statut Éditeur de ${label} ?`);
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

  async function confirmSensitiveAction(message) {
    if (!window.confirm(message)) return false;

    const password = await requestAdminPassword();
    if (password === null) return false;

    try {
      await reauthenticateCurrentAdmin(password);
      return true;
    } catch (error) {
      setStatus(getReauthenticationErrorMessage(error), "error");
      return false;
    }
  }

  async function reauthenticateCurrentAdmin(password) {
    const user = firebase.auth().currentUser;
    const email = user?.email;

    if (!user || !email) {
      throw new Error("Session administrateur introuvable.");
    }

    if (!String(password || "").trim()) {
      throw new Error("Mot de passe requis.");
    }

    const credential = firebase.auth.EmailAuthProvider.credential(email, password);
    await user.reauthenticateWithCredential(credential);
  }

  function getReauthenticationErrorMessage(error) {
    const code = error?.code || "";

    if (code === "auth/wrong-password" || code === "auth/invalid-credential") {
      return "Mot de passe administrateur incorrect.";
    }

    if (code === "auth/too-many-requests") {
      return "Trop de tentatives. Réessaie plus tard.";
    }

    return error?.message || "Confirmation administrateur impossible.";
  }

  function requestAdminPassword() {
    return new Promise((resolve) => {
      const dialog = document.createElement("dialog");
      const form = document.createElement("form");
      const title = document.createElement("h3");
      const description = document.createElement("p");
      const input = document.createElement("input");
      const actions = document.createElement("div");
      const cancelButton = document.createElement("button");
      const confirmButton = document.createElement("button");

      dialog.className = "sensitive-dialog";
      form.method = "dialog";
      title.textContent = "Confirmation administrateur";
      description.textContent = "Entre ton mot de passe pour continuer.";
      input.type = "password";
      input.autocomplete = "current-password";
      input.required = true;
      input.placeholder = "Mot de passe";
      actions.className = "sensitive-dialog-actions";
      cancelButton.type = "button";
      cancelButton.className = "ghost-button";
      cancelButton.textContent = "Annuler";
      confirmButton.type = "submit";
      confirmButton.className = "primary-button compact-save-button";
      confirmButton.textContent = "Confirmer";

      cancelButton.addEventListener("click", () => {
        dialog.close();
        dialog.remove();
        resolve(null);
      });

      form.addEventListener("submit", (event) => {
        event.preventDefault();
        const password = input.value;
        dialog.close();
        dialog.remove();
        resolve(password);
      });

      actions.append(cancelButton, confirmButton);
      form.append(title, description, input, actions);
      dialog.append(form);
      document.body.append(dialog);
      dialog.showModal();
      input.focus();
    });
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

  function formatDuration(value) {
    const seconds = Number(value || 0);
    if (!Number.isFinite(seconds) || seconds <= 0) return "-";

    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = Math.floor(seconds % 60);
    if (minutes <= 0) return `${remainingSeconds}s`;
    return `${minutes} min ${String(remainingSeconds).padStart(2, "0")}s`;
  }

  function getTimestampMillis(value) {
    if (!value) return 0;
    if (typeof value.toMillis === "function") return value.toMillis();
    if (typeof value.toDate === "function") return value.toDate().getTime();
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? 0 : parsed;
  }

  return {
    init,
    start,
    startDetail,
    stop,
  };
})();
