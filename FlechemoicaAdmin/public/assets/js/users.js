const UsersView = (() => {
  let unsubscribe = null;
  let firestore = null;
  let tableBody = null;
  let statusNode = null;
  let searchInput = null;
  let users = [];
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
      cell.colSpan = 5;
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

  function makeActionsCell(id, data) {
    const cell = document.createElement("td");
    const wrapper = document.createElement("div");
    const button = document.createElement("button");
    const menu = document.createElement("div");
    const editorStatusButton = document.createElement("button");
    const isEditor = String(data.status || data.role || "").toLowerCase() === "editor";
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

    if (!(isCurrentUser && isEditor)) {
      editorStatusButton.type = "button";
      editorStatusButton.setAttribute("role", "menuitem");
      editorStatusButton.textContent = isEditor ? "Retirer statut Éditeur" : "Déclarer statut Éditeur";
      editorStatusButton.addEventListener("click", (event) => {
        event.stopPropagation();
        closeOptionsMenus();
        if (isEditor) {
          removeEditorStatus(id, data);
        } else {
          promoteToEditor(id, data);
        }
      });

      menu.append(editorStatusButton);
    }
    wrapper.append(button, menu);
    cell.append(wrapper);
    return cell;
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
