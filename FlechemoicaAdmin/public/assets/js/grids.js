const GridsView = (() => {
  let unsubscribe = null;
  let firestore = null;
  let tableBody = null;
  let tableShell = null;
  let statusNode = null;
  let searchInput = null;
  let addButton = null;
  let importForm = null;
  let importTitleInput = null;
  let importReleaseInput = null;
  let importJsonInput = null;
  let importFileInput = null;
  let importDropZone = null;
  let importCancelButton = null;
  let calendarGrid = null;
  let calendarYearTitle = null;
  let calendarPrevButton = null;
  let calendarNextButton = null;
  let detailTitle = null;
  let detailMeta = null;
  let detailStatusBadge = null;
  let detailStatus = null;
  let detailReleaseInput = null;
  let detailActions = null;
  let previewNode = null;
  let editorForm = null;
  let editorList = null;
  let replaceFileInput = null;
  let replaceDropZone = null;
  let grids = [];
  let calendarYear = getISOWeekParts(new Date()).year;
  let currentDetailID = "";
  let currentDetailData = null;
  let viewLoaded = false;
  let viewLoadPromise = null;
  let documentClickBound = false;

  function init() {
    resolveNodes();

    if (!documentClickBound) {
      document.addEventListener("click", closeGridOptionsMenus);
      documentClickBound = true;
    }
  }

  function resolveNodes() {
    tableBody = document.getElementById("grids-table-body");
    tableShell = document.getElementById("grids-table-shell");
    statusNode = document.getElementById("grids-status");
    searchInput = document.getElementById("grids-search");
    addButton = document.getElementById("add-grid-button");
    importForm = document.getElementById("grid-import-form");
    importTitleInput = document.getElementById("grid-import-title");
    importReleaseInput = document.getElementById("grid-import-release");
    importJsonInput = document.getElementById("grid-import-json");
    importFileInput = document.getElementById("grid-json-file");
    importDropZone = document.getElementById("grid-json-drop-zone");
    importCancelButton = document.getElementById("grid-import-cancel");
    calendarGrid = document.getElementById("year-calendar-grid");
    calendarYearTitle = document.getElementById("calendar-year-title");
    calendarPrevButton = document.getElementById("calendar-prev-year");
    calendarNextButton = document.getElementById("calendar-next-year");
    detailTitle = document.getElementById("grid-detail-title");
    detailMeta = document.getElementById("grid-detail-meta");
    detailStatusBadge = document.getElementById("grid-detail-status-badge");
    detailStatus = document.getElementById("grid-detail-status");
    detailReleaseInput = document.getElementById("grid-detail-release");
    detailActions = document.getElementById("grid-detail-actions");
    previewNode = document.getElementById("grid-preview");
    editorForm = document.getElementById("grid-editor-form");
    editorList = document.getElementById("grid-editor-list");
    replaceFileInput = document.getElementById("grid-replace-file");
    replaceDropZone = document.getElementById("grid-replace-drop-zone");

    if (searchInput && !searchInput.dataset.bound) {
      searchInput.addEventListener("input", () => renderGrids(filterGrids()));
      searchInput.dataset.bound = "true";
    }

    if (addButton && !addButton.dataset.bound) {
      addButton.addEventListener("click", toggleImportForm);
      addButton.dataset.bound = "true";
    }

    if (importCancelButton && !importCancelButton.dataset.bound) {
      importCancelButton.addEventListener("click", hideImportForm);
      importCancelButton.dataset.bound = "true";
    }

    if (importForm && !importForm.dataset.bound) {
      importForm.addEventListener("submit", addGridFromImport);
      importForm.dataset.bound = "true";
    }

    if (importFileInput && !importFileInput.dataset.bound) {
      importFileInput.addEventListener("change", () => {
        const file = importFileInput.files?.[0];
        if (file) loadJsonFile(file);
      });
      importFileInput.dataset.bound = "true";
    }

    if (importDropZone && !importDropZone.dataset.bound) {
      importDropZone.addEventListener("click", () => importFileInput?.click());
      importDropZone.addEventListener("keydown", (event) => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          importFileInput?.click();
        }
      });
      importDropZone.addEventListener("dragover", handleJsonDragOver);
      importDropZone.addEventListener("dragleave", handleJsonDragLeave);
      importDropZone.addEventListener("drop", handleJsonDrop);
      importDropZone.dataset.bound = "true";
    }

    if (calendarPrevButton && !calendarPrevButton.dataset.bound) {
      calendarPrevButton.addEventListener("click", () => {
        calendarYear -= 1;
        renderCalendar();
      });
      calendarPrevButton.dataset.bound = "true";
    }

    if (calendarNextButton && !calendarNextButton.dataset.bound) {
      calendarNextButton.addEventListener("click", () => {
        calendarYear += 1;
        renderCalendar();
      });
      calendarNextButton.dataset.bound = "true";
    }

    if (editorForm && !editorForm.dataset.bound) {
      editorForm.addEventListener("submit", saveGridCorrections);
      editorForm.dataset.bound = "true";
    }

    if (replaceFileInput && !replaceFileInput.dataset.bound) {
      replaceFileInput.addEventListener("change", () => {
        const file = replaceFileInput.files?.[0];
        if (file) replaceCurrentGridFromFile(file);
      });
      replaceFileInput.dataset.bound = "true";
    }

    if (replaceDropZone && !replaceDropZone.dataset.bound) {
      replaceDropZone.addEventListener("click", () => replaceFileInput?.click());
      replaceDropZone.addEventListener("keydown", (event) => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          replaceFileInput?.click();
        }
      });
      replaceDropZone.addEventListener("dragover", (event) => {
        event.preventDefault();
        replaceDropZone.classList.add("is-dragging");
      });
      replaceDropZone.addEventListener("dragleave", (event) => {
        event.preventDefault();
        replaceDropZone.classList.remove("is-dragging");
      });
      replaceDropZone.addEventListener("drop", (event) => {
        event.preventDefault();
        replaceDropZone.classList.remove("is-dragging");
        const file = event.dataTransfer?.files?.[0];
        if (file) replaceCurrentGridFromFile(file);
      });
      replaceDropZone.dataset.bound = "true";
    }
  }

  async function ensureView() {
    if (viewLoaded) {
      resolveNodes();
      return;
    }

    if (!viewLoadPromise) {
      viewLoadPromise = loadView("grids-panel", "Vue grilles introuvable.");
    }

    await viewLoadPromise;
    viewLoaded = true;
    resolveNodes();
  }

  async function ensureDetailView() {
    const panel = document.getElementById("grid-detail-panel");
    if (!panel) throw new Error("Panneau fiche grille introuvable.");

    if (!panel.innerHTML.trim()) {
      await loadView("grid-detail-panel", "Vue fiche grille introuvable.");
    }

    resolveNodes();
  }

  async function loadView(panelID, errorMessage) {
    const panel = document.getElementById(panelID);
    if (!panel) throw new Error("Panneau introuvable.");

    const viewSrc = panel.dataset.viewSrc;
    if (viewSrc && !panel.innerHTML.trim()) {
      const response = await fetch(viewSrc, { cache: "no-store" });
      if (!response.ok) throw new Error(errorMessage);
      panel.innerHTML = await response.text();
    }
  }

  function setStatus(message, tone = "") {
    if (!statusNode) return;
    statusNode.textContent = message;
    statusNode.dataset.tone = tone;
  }

  function setDetailStatus(message, tone = "") {
    if (!detailStatus) return;
    detailStatus.textContent = message;
    detailStatus.dataset.tone = tone;
  }

  async function start() {
    try {
      await ensureView();
      await ensureFirestore();
      if (unsubscribe) return;

      setStatus("Chargement...");
      unsubscribe = firestore.collection("grids").onSnapshot(
        (snapshot) => {
          grids = snapshot.docs;
          renderCalendar();
          renderGrids(filterGrids());
        },
        (error) => {
          setStatus(error.message || "Impossible de charger les grilles.", "error");
        }
      );
    } catch (error) {
      resolveNodes();
      setStatus(error.message || "Impossible de charger la page grilles.", "error");
    }
  }

  async function startDetail(gridID) {
    currentDetailID = gridID;

    try {
      await ensureDetailView();
      await ensureFirestore();
      await renderGridDetail(gridID);
    } catch (error) {
      resolveNodes();
      setDetailStatus(error.message || "Impossible de charger la fiche grille.", "error");
    }
  }

  function stop() {
    if (!unsubscribe) return;
    unsubscribe();
    unsubscribe = null;
  }

  async function ensureFirestore() {
    if (firestore) return;

    const services = AuthGate.ensureFirebase();
    firestore = services.firestore;

    if (!firestore) {
      throw new Error("Firestore indisponible.");
    }
  }

  function renderGrids(docs) {
    if (!tableBody) return;

    tableShell?.classList.remove("is-hidden");
    tableBody.replaceChildren();

    if (!docs.length) {
      const row = document.createElement("tr");
      const cell = document.createElement("td");
      cell.colSpan = 5;
      cell.className = "empty-cell";
      cell.textContent = "Aucune grille.";
      row.append(cell);
      tableBody.append(row);
      setStatus(normalizeSearch(searchInput?.value) ? "Aucun résultat." : "");
      return;
    }

    const sortedDocs = [...docs].sort(compareGridDocs);
    const fragment = document.createDocumentFragment();
    sortedDocs.forEach((doc) => fragment.append(createGridRow(doc.id, doc.data())));
    tableBody.append(fragment);
    setStatus("");
  }

  function renderCalendar() {
    if (!calendarGrid || !calendarYearTitle) return;

    calendarYearTitle.textContent = String(calendarYear);
    calendarGrid.replaceChildren();

    const weeks = buildCalendarWeeks(calendarYear);
    const fragment = document.createDocumentFragment();

    weeks.forEach((week) => {
      const button = document.createElement("button");
      const label = document.createElement("span");
      const title = document.createElement("span");

      button.className = "calendar-week";
      button.type = "button";
      button.dataset.status = week.status;
      button.disabled = !week.doc;
      button.setAttribute("aria-label", week.ariaLabel);

      if (week.doc) {
        button.addEventListener("click", () => openGridDetail(week.doc.id));
      }

      label.className = "calendar-week-number";
      label.textContent = `S${String(week.week).padStart(2, "0")}`;
      title.className = "calendar-week-title";
      title.textContent = week.title;

      button.append(label, title);
      fragment.append(button);
    });

    calendarGrid.append(fragment);
  }

  function buildCalendarWeeks(year) {
    const gridsByWeek = new Map();

    grids.forEach((doc) => {
      const data = doc.data();
      const weekParts = getGridWeekParts(data);
      if (!weekParts || weekParts.year !== year) return;

      const key = weekParts.week;
      const entries = gridsByWeek.get(key) || [];
      entries.push({ doc, data });
      gridsByWeek.set(key, entries);
    });

    const weekCount = getWeeksInISOYear(year);
    return Array.from({ length: weekCount }, (_, index) => {
      const week = index + 1;
      const entries = gridsByWeek.get(week) || [];
      const entry = pickCalendarEntry(entries);
      const status = getCalendarStatus(entries);
      const title = entry ? (entry.data.title || getGridPayload(entry.data).name || "Grille") : "";
      const ariaLabel = entry
        ? `Semaine ${week}, ${title}, ${entry.data.status || "statut inconnu"}`
        : `Semaine ${week}, aucune grille`;

      return {
        week,
        doc: entry?.doc || null,
        status,
        title,
        ariaLabel,
      };
    });
  }

  function pickCalendarEntry(entries) {
    if (!entries.length) return null;

    return [...entries].sort((left, right) => {
      const statusWeight = getStatusWeight(right.data.status) - getStatusWeight(left.data.status);
      if (statusWeight !== 0) return statusWeight;
      return getTimestampMillis(right.data.releaseAt) - getTimestampMillis(left.data.releaseAt);
    })[0];
  }

  function getCalendarStatus(entries) {
    if (!entries.length) return "empty";
    if (entries.some((entry) => normalizeStatus(entry.data.status) === "published")) return "published";
    if (entries.some((entry) => normalizeStatus(entry.data.status) === "scheduled")) return "scheduled";
    return "filled";
  }

  function getStatusWeight(status) {
    const normalized = normalizeStatus(status);
    if (normalized === "published") return 2;
    if (normalized === "scheduled") return 1;
    return 0;
  }

  function filterGrids() {
    const query = normalizeSearch(searchInput?.value);
    if (!query) return grids;

    return grids.filter((doc) => {
      const data = doc.data();
      const grid = getGridPayload(data);
      const placedWords = Array.isArray(grid.placedWords) ? grid.placedWords : [];
      return [
        doc.id,
        data.title,
        data.weekId,
        data.status,
        grid.name,
        ...placedWords.flatMap((entry) => [entry.word, ...getDefinitions(entry)]),
      ].some((value) => normalizeSearch(value).includes(query));
    });
  }

  function createGridRow(id, data) {
    const grid = getGridPayload(data);
    const row = document.createElement("tr");

    row.className = "clickable-row";
    row.addEventListener("click", () => openGridDetail(id));

    row.append(
      makeIdentityCell(data.title || grid.name || "Grille", id),
      makeBadgeCell(data.status || "-"),
      makeTextCell(data.weekId || "-"),
      makeTextCell(formatValue(data.releaseAt)),
      makeActionsCell(id, data)
    );

    return row;
  }

  function makeIdentityCell(title, metaValue) {
    const cell = document.createElement("td");
    const name = document.createElement("a");
    const meta = document.createElement("span");

    name.className = "table-link";
    name.href = `/grille/${encodeURIComponent(metaValue)}.html`;
    name.textContent = title;
    name.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      openGridDetail(metaValue);
    });
    meta.textContent = metaValue;

    cell.append(name, meta);
    return cell;
  }

  function makeTextCell(value) {
    const cell = document.createElement("td");
    cell.textContent = value == null || value === "" ? "-" : String(value);
    return cell;
  }

  function makeBadgeCell(value) {
    const cell = document.createElement("td");
    const badge = document.createElement("span");
    renderStatusBadge(badge, value);
    cell.append(badge);
    return cell;
  }

  function makeActionsCell(id, data) {
    const cell = document.createElement("td");
    const wrapper = document.createElement("div");
    const button = document.createElement("button");
    const menu = document.createElement("div");
    const isBlocked = normalizeStatus(data.status) === "blocked";

    cell.className = "actions-cell";
    wrapper.className = "options-menu-wrap";

    button.className = "options-button";
    button.type = "button";
    button.textContent = "...";
    button.setAttribute("aria-label", `Options pour ${data.title || "cette grille"}`);
    button.setAttribute("aria-expanded", "false");
    button.addEventListener("click", (event) => {
      event.stopPropagation();
      toggleGridOptionsMenu(menu, button);
    });

    menu.className = "options-menu is-hidden";
    menu.setAttribute("role", "menu");
    menu.append(
      createGridMenuButton("Modifier la date de publication", () => editGridReleaseDate(id, data)),
      createGridMenuButton(isBlocked ? "Débloquer l'accès" : "Bloquer l'accès", () => setGridAccessBlocked(id, data, !isBlocked)),
      createGridMenuButton("Supprimer", () => deleteGrid(id, data), "danger")
    );

    wrapper.append(button, menu);
    cell.append(wrapper);
    return cell;
  }

  function createGridMenuButton(label, action, tone = "") {
    const menuButton = document.createElement("button");
    menuButton.type = "button";
    menuButton.setAttribute("role", "menuitem");
    menuButton.textContent = label;
    if (tone) menuButton.dataset.tone = tone;
    menuButton.addEventListener("click", (event) => {
      event.stopPropagation();
      closeGridOptionsMenus();
      action();
    });
    return menuButton;
  }

  function toggleGridOptionsMenu(menu, button) {
    const shouldOpen = menu.classList.contains("is-hidden");
    closeGridOptionsMenus();

    if (shouldOpen) {
      menu.classList.remove("is-hidden");
      button.setAttribute("aria-expanded", "true");
    }
  }

  function closeGridOptionsMenus() {
    document.querySelectorAll("#grids-panel .options-menu").forEach((menu) => {
      menu.classList.add("is-hidden");
    });

    document.querySelectorAll("#grids-panel .options-button[aria-expanded='true']").forEach((button) => {
      button.setAttribute("aria-expanded", "false");
    });
  }

  function renderStatusBadge(node, value) {
    if (!node) return;

    node.className = "status-badge";
    const normalized = String(value || "").toLowerCase();
    if (normalized === "published") {
      node.classList.add("status-badge-published");
    } else if (normalized === "scheduled") {
      node.classList.add("status-badge-scheduled");
    } else if (normalized === "blocked") {
      node.classList.add("status-badge-blocked");
    }
    node.textContent = value;
  }

  async function editGridReleaseDate(id, data) {
    const currentDate = getDateFromValue(data.releaseAt);
    const currentValue = currentDate ? formatDateTimeLocal(currentDate) : formatDateTimeLocal(getNextWednesdayAt17());
    const nextValue = window.prompt("Nouvelle date de publication", currentValue);
    if (!nextValue) return;

    const releaseAt = new Date(nextValue);
    if (!Number.isFinite(releaseAt.getTime())) {
      setStatus("Date de publication invalide.", "error");
      return;
    }

    try {
      setStatus("Mise à jour de la date...");
      await firestore.collection("grids").doc(id).set({
        releaseAt: firebase.firestore.Timestamp.fromDate(releaseAt),
        weekId: getISOWeekID(releaseAt),
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      setStatus("Date de publication mise à jour.");
    } catch (error) {
      setStatus(error.message || "Impossible de modifier la date.", "error");
    }
  }

  async function setGridAccessBlocked(id, data, shouldBlock) {
    const title = data.title || "cette grille";
    const message = shouldBlock
      ? `Bloquer l'accès à ${title} ? Elle ne sera plus visible dans l'application.`
      : `Débloquer l'accès à ${title} ?`;
    const shouldContinue = shouldBlock
      ? await confirmSensitiveAction(message)
      : window.confirm(message);
    if (!shouldContinue) return;

    const releaseDate = getDateFromValue(data.releaseAt);
    const restoredStatus = releaseDate && releaseDate > new Date() ? "scheduled" : "published";

    try {
      setStatus(shouldBlock ? "Blocage de l'accès..." : "Déblocage de l'accès...");
      await firestore.collection("grids").doc(id).set({
        status: shouldBlock ? "blocked" : restoredStatus,
        accessBlockedAt: shouldBlock ? firebase.firestore.FieldValue.serverTimestamp() : firebase.firestore.FieldValue.delete(),
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      if (currentDetailID === id) {
        const nextData = { ...data, status: shouldBlock ? "blocked" : restoredStatus };
        renderStatusBadge(detailStatusBadge, nextData.status);
        renderGridDetailActions(id, nextData);
      }
      setStatus(shouldBlock ? "Accès bloqué." : "Accès débloqué.");
    } catch (error) {
      setStatus(error.message || "Impossible de modifier l'accès.", "error");
    }
  }

  async function deleteGrid(id, data) {
    const title = data.title || "cette grille";
    const shouldDelete = await confirmSensitiveAction(`Supprimer définitivement ${title} ?`);
    if (!shouldDelete) return;

    try {
      setStatus("Suppression...");
      await firestore.collection("grids").doc(id).delete();
      setStatus("Grille supprimée.");
      if (currentDetailID === id) {
        currentDetailID = "";
        document.querySelector("[data-panel-target='grids-panel']")?.click();
      }
    } catch (error) {
      setStatus(error.message || "Impossible de supprimer la grille.", "error");
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

  function openGridDetail(gridID) {
    const path = `/grille/${encodeURIComponent(gridID)}.html`;
    window.history.pushState({ panelID: "grid-detail-panel", gridID }, "", path);
    DashboardView.showGridDetail(gridID);
  }

  async function renderGridDetail(gridID) {
    const doc = grids.find((entry) => entry.id === gridID) || await getGridDoc(gridID);
    const data = doc.data();
    const grid = getGridPayload(data);
    const placedWords = Array.isArray(grid.placedWords) ? grid.placedWords : [];
    const title = data.title || grid.name || "Grille";

    currentDetailData = { id: doc.id, data, grid, placedWords };

    if (detailTitle) detailTitle.textContent = title;
    if (detailMeta) detailMeta.textContent = `ID : ${doc.id}`;
    renderStatusBadge(detailStatusBadge, data.status || "-");
    if (detailReleaseInput) {
      const releaseDate = getDateFromValue(data.releaseAt);
      detailReleaseInput.value = releaseDate ? formatDateTimeLocal(releaseDate) : "";
    }
    setDetailStatus("");
    renderGridPreview(grid);
    renderGridDetailActions(doc.id, data);
    renderGridEditor(placedWords);
  }

  function renderGridDetailActions(id, data) {
    if (!detailActions) return;

    const isBlocked = normalizeStatus(data.status) === "blocked";
    detailActions.replaceChildren(
      makeDetailActionButton("Publier maintenant", () => publishGridNow(id, data)),
      makeDetailActionButton(
        isBlocked ? "Débloquer l'accès" : "Bloquer l'accès",
        () => setGridAccessBlocked(id, data, !isBlocked)
      ),
      makeDetailActionButton("Supprimer la grille", () => deleteGrid(id, data), "danger")
    );
  }

  function makeDetailActionButton(label, action, tone = "") {
    const button = document.createElement("button");
    button.type = "button";
    button.className = tone === "danger" ? "ghost-button detail-danger-button" : "ghost-button";
    button.textContent = label;
    button.addEventListener("click", action);
    return button;
  }

  async function publishGridNow(id, data) {
    const title = data.title || "cette grille";
    if (!window.confirm(`Publier ${title} maintenant ?`)) return;

    const now = new Date();
    try {
      setDetailStatus("Publication...");
      await firestore.collection("grids").doc(id).set({
        status: "published",
        releaseAt: firebase.firestore.Timestamp.fromDate(now),
        weekId: getISOWeekID(now),
        accessBlockedAt: firebase.firestore.FieldValue.delete(),
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      if (detailReleaseInput) {
        detailReleaseInput.value = formatDateTimeLocal(now);
      }
      renderStatusBadge(detailStatusBadge, "published");
      renderGridDetailActions(id, { ...data, status: "published" });
      setDetailStatus("Grille publiée.");
    } catch (error) {
      setDetailStatus(error.message || "Impossible de publier la grille.", "error");
    }
  }

  async function getGridDoc(gridID) {
    if (!gridID) throw new Error("Grille introuvable.");

    const snapshot = await firestore.collection("grids").doc(gridID).get();
    if (!snapshot.exists) throw new Error("Grille introuvable.");
    return snapshot;
  }

  function renderGridPreview(grid) {
    if (!previewNode) return;
    previewNode.replaceChildren();

    const placedWords = Array.isArray(grid.placedWords) ? grid.placedWords : [];
    const cells = buildGridCells(grid);
    const title = document.createElement("h3");
    const board = document.createElement("div");
    title.textContent = "Grille";
    board.className = "grid-board";
    board.style.setProperty("--grid-columns", String(cells.columnCount));

    for (let row = 0; row < cells.rowCount; row += 1) {
      for (let column = 0; column < cells.columnCount; column += 1) {
        const cell = document.createElement("span");
        const key = `${row}:${column}`;
        cell.className = cells.blackCells.has(key) ? "grid-board-cell is-black" : "grid-board-cell";
        cell.textContent = cells.letters.get(key) || "";
        board.append(cell);
      }
    }

    const summary = document.createElement("p");
    summary.className = "panel-status";
    summary.textContent = `${placedWords.length} mots`;
    previewNode.append(title, board, summary);
  }

  function buildGridCells(grid) {
    const placedWords = Array.isArray(grid.placedWords) ? grid.placedWords : [];
    const blackCells = new Set((grid.blackCells || []).map((cell) => `${cell.row}:${cell.column}`));
    const letters = new Map();
    let maxRow = 0;
    let maxColumn = 0;

    placedWords.forEach((entry) => {
      const start = getWordStart(entry);
      const direction = getWordDirection(entry);
      const word = String(entry.word || "");

      for (let index = 0; index < word.length; index += 1) {
        const row = start.row + direction.rowDelta * index;
        const column = start.column + direction.columnDelta * index;
        letters.set(`${row}:${column}`, word[index]);
        maxRow = Math.max(maxRow, row);
        maxColumn = Math.max(maxColumn, column);
      }
    });

    blackCells.forEach((key) => {
      const [row, column] = key.split(":").map(Number);
      maxRow = Math.max(maxRow, row);
      maxColumn = Math.max(maxColumn, column);
    });

    return {
      blackCells,
      letters,
      rowCount: Math.max(maxRow + 1, 1),
      columnCount: Math.max(maxColumn + 1, 1),
    };
  }

  function getWordStart(entry) {
    const cell = entry.definitionCell || {};
    const direction = entry.direction || {};
    return {
      row: Number(cell.row || 0) + Number(direction.startRowDelta || 0),
      column: Number(cell.column || 0) + Number(direction.startColumnDelta || 0),
    };
  }

  function getWordDirection(entry) {
    const direction = entry.direction || {};
    return {
      rowDelta: Number(direction.rowDelta || 0),
      columnDelta: Number(direction.columnDelta || 0),
    };
  }

  function renderGridEditor(placedWords) {
    if (!editorList) return;
    editorList.replaceChildren();

    placedWords.forEach((entry, index) => {
      const item = document.createElement("div");
      const wordGroup = document.createElement("div");
      const definitionGroup = document.createElement("div");
      const wordLabel = document.createElement("label");
      const definitionLabel = document.createElement("label");
      const wordInput = document.createElement("input");
      const definitionTextarea = document.createElement("textarea");

      item.className = "grid-editor-item";
      wordGroup.className = "field-group";
      definitionGroup.className = "field-group";
      wordLabel.textContent = "Mot";
      definitionLabel.textContent = "Définition";
      wordInput.value = entry.word || "";
      wordInput.dataset.wordIndex = String(index);
      definitionTextarea.rows = 2;
      definitionTextarea.value = getDefinitions(entry).join("\n");
      definitionTextarea.dataset.definitionIndex = String(index);

      wordGroup.append(wordLabel, wordInput);
      definitionGroup.append(definitionLabel, definitionTextarea);
      item.append(wordGroup, definitionGroup);
      editorList.append(item);
    });
  }

  async function saveGridCorrections(event) {
    event.preventDefault();

    if (!currentDetailData) return;

    const nextWords = currentDetailData.placedWords.map((entry, index) => {
      const wordInput = editorList.querySelector(`[data-word-index="${index}"]`);
      const definitionInput = editorList.querySelector(`[data-definition-index="${index}"]`);
      return {
        ...entry,
        word: String(wordInput?.value || "").trim().toUpperCase(),
        definitions: String(definitionInput?.value || "")
          .split("\n")
          .map((definition) => definition.trim())
          .filter(Boolean),
      };
    });
    const releaseAt = detailReleaseInput?.value ? new Date(detailReleaseInput.value) : null;

    if (!releaseAt || !Number.isFinite(releaseAt.getTime())) {
      setDetailStatus("Date de publication invalide.", "error");
      return;
    }

    try {
      setDetailStatus("Enregistrement...");
      await firestore.collection("grids").doc(currentDetailData.id).set({
        placedWords: nextWords,
        releaseAt: firebase.firestore.Timestamp.fromDate(releaseAt),
        weekId: getISOWeekID(releaseAt),
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      setDetailStatus("Corrections enregistrées.");
      currentDetailData.placedWords = nextWords;
      currentDetailData.grid.placedWords = nextWords;
      currentDetailData.data.releaseAt = firebase.firestore.Timestamp.fromDate(releaseAt);
      currentDetailData.data.weekId = getISOWeekID(releaseAt);
      if (detailMeta) {
        detailMeta.textContent = `ID : ${currentDetailData.id}`;
      }
      renderStatusBadge(detailStatusBadge, currentDetailData.data.status || "-");
      renderGridPreview(currentDetailData.grid);
    } catch (error) {
      setDetailStatus(error.message || "Impossible d'enregistrer les corrections.", "error");
    }
  }

  async function replaceCurrentGridFromFile(file) {
    try {
      if (!currentDetailData) throw new Error("Grille introuvable.");
      if (!file.name.toLowerCase().endsWith(".json")) {
        throw new Error("Le fichier doit être un JSON.");
      }

      const content = await file.text();
      const grid = JSON.parse(content);

      if (!grid || typeof grid !== "object") throw new Error("JSON invalide.");
      if (!Array.isArray(grid.placedWords)) throw new Error("Le JSON doit contenir placedWords.");

      const shouldReplace = window.confirm("Remplacer entièrement le contenu de cette grille par ce JSON ?");
      if (!shouldReplace) return;

      setDetailStatus("Remplacement de la grille...");
      await firestore.collection("grids").doc(currentDetailData.id).set({
        blackCells: Array.isArray(grid.blackCells) ? grid.blackCells : [],
        name: grid.name || currentDetailData.grid.name || currentDetailData.data.title || "",
        placedWords: grid.placedWords,
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      currentDetailData.grid = {
        blackCells: Array.isArray(grid.blackCells) ? grid.blackCells : [],
        name: grid.name || currentDetailData.grid.name,
        placedWords: grid.placedWords,
      };
      currentDetailData.placedWords = grid.placedWords;
      renderGridPreview(currentDetailData.grid);
      renderGridEditor(currentDetailData.placedWords);
      setDetailStatus("Grille remplacée.");
    } catch (error) {
      setDetailStatus(error.message || "Impossible de remplacer la grille.", "error");
    } finally {
      if (replaceFileInput) replaceFileInput.value = "";
    }
  }

  function toggleImportForm() {
    if (!importForm) return;

    if (importForm.classList.contains("is-hidden")) {
      showImportForm();
      return;
    }

    hideImportForm();
  }

  function showImportForm() {
    if (!importForm) return;
    importForm.classList.remove("is-hidden");
    if (addButton) {
      addButton.textContent = "-";
      addButton.setAttribute("aria-label", "Masquer l'ajout de grille");
    }
    if (importReleaseInput && !importReleaseInput.value) {
      importReleaseInput.value = formatDateTimeLocal(getNextWednesdayAt17());
    }
    importTitleInput?.focus();
  }

  function hideImportForm() {
    importForm?.classList.add("is-hidden");
    if (addButton) {
      addButton.textContent = "+";
      addButton.setAttribute("aria-label", "Afficher l'ajout de grille");
    }
  }

  function handleJsonDragOver(event) {
    event.preventDefault();
    importDropZone?.classList.add("is-dragging");
  }

  function handleJsonDragLeave(event) {
    event.preventDefault();
    importDropZone?.classList.remove("is-dragging");
  }

  function handleJsonDrop(event) {
    event.preventDefault();
    importDropZone?.classList.remove("is-dragging");

    const file = event.dataTransfer?.files?.[0];
    if (file) loadJsonFile(file);
  }

  async function loadJsonFile(file) {
    try {
      if (!file.name.toLowerCase().endsWith(".json")) {
        throw new Error("Le fichier doit être un JSON.");
      }

      const content = await file.text();
      JSON.parse(content);

      if (importJsonInput) importJsonInput.value = content;
      if (importTitleInput && !importTitleInput.value.trim()) {
        importTitleInput.value = file.name.replace(/\.json$/i, "");
      }
      setStatus("JSON chargé.");
    } catch (error) {
      setStatus(error.message || "Impossible de lire le fichier JSON.", "error");
    }
  }

  async function addGridFromImport(event) {
    event.preventDefault();

    try {
      await ensureFirestore();
      const title = String(importTitleInput?.value || "").trim();
      const releaseValue = importReleaseInput?.value;
      const grid = JSON.parse(importJsonInput?.value || "");
      const releaseAt = releaseValue ? new Date(releaseValue) : getNextWednesdayAt17();

      if (!title) throw new Error("Titre requis.");
      if (!Number.isFinite(releaseAt.getTime())) throw new Error("Date de publication invalide.");
      if (!grid || typeof grid !== "object") throw new Error("JSON invalide.");
      if (!Array.isArray(grid.placedWords)) throw new Error("Le JSON doit contenir placedWords.");

      setStatus("Ajout de la grille...");
      await firestore.collection("grids").add({
        ...grid,
        title,
        status: "scheduled",
        weekId: getISOWeekID(releaseAt),
        releaseAt: firebase.firestore.Timestamp.fromDate(releaseAt),
        createdAt: firebase.firestore.FieldValue.serverTimestamp(),
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      });

      importForm.reset();
      hideImportForm();
      setStatus("Grille ajoutée et planifiée.");
    } catch (error) {
      setStatus(error.message || "Impossible d'ajouter la grille.", "error");
    }
  }

  function getNextWednesdayAt17() {
    const date = new Date();
    date.setSeconds(0, 0);
    date.setHours(17, 0, 0, 0);

    const day = date.getDay();
    const daysUntilWednesday = (3 - day + 7) % 7;
    date.setDate(date.getDate() + daysUntilWednesday);

    if (date <= new Date()) {
      date.setDate(date.getDate() + 7);
    }

    return date;
  }

  function formatDateTimeLocal(date) {
    const pad = (value) => String(value).padStart(2, "0");
    return [
      date.getFullYear(),
      pad(date.getMonth() + 1),
      pad(date.getDate()),
    ].join("-") + `T${pad(date.getHours())}:${pad(date.getMinutes())}`;
  }

  function getISOWeekID(date) {
    const parts = getISOWeekParts(date);
    return `${parts.year}-W${String(parts.week).padStart(2, "0")}`;
  }

  function getISOWeekParts(date) {
    const target = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
    const day = target.getUTCDay() || 7;
    target.setUTCDate(target.getUTCDate() + 4 - day);
    const yearStart = new Date(Date.UTC(target.getUTCFullYear(), 0, 1));
    const week = Math.ceil((((target - yearStart) / 86400000) + 1) / 7);
    return { year: target.getUTCFullYear(), week };
  }

  function getWeeksInISOYear(year) {
    return getISOWeekParts(new Date(year, 11, 28)).week;
  }

  function getGridWeekParts(data) {
    const releaseDate = getDateFromValue(data.releaseAt);
    if (releaseDate) return getISOWeekParts(releaseDate);

    const match = String(data.weekId || "").match(/^(\d{4})-W(\d{1,2})$/);
    if (!match) return null;

    return {
      year: Number(match[1]),
      week: Number(match[2]),
    };
  }

  function getGridPayload(data) {
    const directPayload = {
      blackCells: data.blackCells,
      name: data.name,
      placedWords: data.placedWords,
    };

    if (Array.isArray(directPayload.placedWords) || Array.isArray(directPayload.blackCells)) {
      return directPayload;
    }

    const candidates = [data.grid, data.data, data.content, data.json, data.payload];

    for (const candidate of candidates) {
      if (!candidate) continue;

      if (typeof candidate === "string") {
        try {
          const parsed = JSON.parse(candidate);
          if (parsed && typeof parsed === "object") return parsed;
        } catch {
          continue;
        }
      }

      if (typeof candidate === "object") return candidate;
    }

    return directPayload;
  }

  function getDefinitions(entry) {
    if (Array.isArray(entry.definitions)) return entry.definitions.filter(Boolean);
    if (entry.definition) return [entry.definition];
    return [];
  }

  function compareGridDocs(left, right) {
    const leftData = left.data();
    const rightData = right.data();
    const leftDate = getTimestampMillis(leftData.releaseAt);
    const rightDate = getTimestampMillis(rightData.releaseAt);

    if (leftDate !== rightDate) return rightDate - leftDate;
    return String(leftData.weekId || "").localeCompare(String(rightData.weekId || ""));
  }

  function getTimestampMillis(value) {
    if (!value) return 0;
    if (typeof value.toMillis === "function") return value.toMillis();
    if (typeof value.toDate === "function") return value.toDate().getTime();
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? 0 : parsed;
  }

  function getDateFromValue(value) {
    if (!value) return null;
    if (typeof value.toDate === "function") return value.toDate();
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }

  function normalizeSearch(value) {
    return String(value || "")
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .trim();
  }

  function normalizeStatus(value) {
    return String(value || "").trim().toLowerCase();
  }

  function formatValue(value) {
    if (value == null || value === "") return "-";

    if (typeof value.toDate === "function") {
      return value.toDate().toLocaleString("fr-FR", {
        dateStyle: "short",
        timeStyle: "short",
      });
    }

    return String(value);
  }

  return {
    init,
    start,
    startDetail,
    stop,
  };
})();
