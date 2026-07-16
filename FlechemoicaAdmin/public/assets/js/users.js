const UsersView = (() => {
  let unsubscribe = null;
  let firestore = null;
  let tableBody = null;
  let statusNode = null;
  let searchInput = null;
  let users = [];
  let viewLoaded = false;
  let viewLoadPromise = null;

  function init() {
    resolveNodes();
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
      cell.colSpan = 4;
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
      makeTextCell(data.email || data.emailKey || "-"),
      makeStatusCell(data.status || data.role || "Utilisateur"),
      makeTextCell(formatValue(data.createdAt))
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

  function makeStatusCell(value) {
    const cell = document.createElement("td");
    const badge = document.createElement("span");
    cell.className = "role-cell";
    badge.className = "status-badge";
    badge.textContent = value;
    cell.append(badge);
    return cell;
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
