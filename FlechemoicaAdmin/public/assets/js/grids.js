const GridsView = (() => {
  let unsubscribe = null;
  let firestore = null;
  let tableBody = null;
  let statusNode = null;
  let searchInput = null;
  let grids = [];
  let viewLoaded = false;
  let viewLoadPromise = null;

  function init() {
    resolveNodes();
  }

  function resolveNodes() {
    tableBody = document.getElementById("grids-table-body");
    statusNode = document.getElementById("grids-status");
    searchInput = document.getElementById("grids-search");

    if (searchInput && !searchInput.dataset.bound) {
      searchInput.addEventListener("input", () => renderGrids(filterGrids()));
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
    const panel = document.getElementById("grids-panel");
    if (!panel) throw new Error("Panneau grilles introuvable.");

    const viewSrc = panel.dataset.viewSrc;
    if (viewSrc && !panel.innerHTML.trim()) {
      const response = await fetch(viewSrc, { cache: "no-store" });
      if (!response.ok) throw new Error("Vue grilles introuvable.");
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
      unsubscribe = firestore.collection("grids").onSnapshot(
        (snapshot) => {
          grids = snapshot.docs;
          renderGrids(filterGrids());
          setStatus("");
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

  function stop() {
    if (!unsubscribe) return;
    unsubscribe();
    unsubscribe = null;
  }

  function renderGrids(docs) {
    if (!tableBody) return;

    tableBody.replaceChildren();

    if (!docs.length) {
      const row = document.createElement("tr");
      const cell = document.createElement("td");
      cell.colSpan = 8;
      cell.className = "empty-cell";
      cell.textContent = "Aucune grille.";
      row.append(cell);
      tableBody.append(row);
      return;
    }

    const sortedDocs = [...docs].sort(compareGridDocs);
    const fragment = document.createDocumentFragment();
    sortedDocs.forEach((doc) => fragment.append(createGridRow(doc.id, doc.data())));
    tableBody.append(fragment);
  }

  function filterGrids() {
    const query = normalizeSearch(searchInput?.value);
    if (!query) return grids;

    return grids.filter((doc) => {
      const data = doc.data();
      const grid = getGridPayload(data);
      return [
        doc.id,
        data.title,
        data.weekId,
        data.status,
        grid.name,
        ...(grid.placedWords || []).map((entry) => entry.word),
      ].some((value) => normalizeSearch(value).includes(query));
    });
  }

  function createGridRow(id, data) {
    const grid = getGridPayload(data);
    const placedWords = Array.isArray(grid.placedWords) ? grid.placedWords : [];
    const blackCells = Array.isArray(grid.blackCells) ? grid.blackCells : [];
    const row = document.createElement("tr");

    row.append(
      makeIdentityCell(data.title || grid.name || "Grille", id),
      makeTextCell(grid.name || "-"),
      makeBadgeCell(data.status || "-"),
      makeTextCell(data.weekId || "-"),
      makeTextCell(formatValue(data.releaseAt)),
      makeTextCell(placedWords.length),
      makeTextCell(blackCells.length),
      makeWordsCell(placedWords)
    );

    return row;
  }

  function makeIdentityCell(title, metaValue) {
    const cell = document.createElement("td");
    const name = document.createElement("strong");
    const meta = document.createElement("span");

    name.textContent = title;
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
    badge.className = "status-badge";
    badge.textContent = value;
    cell.append(badge);
    return cell;
  }

  function makeWordsCell(placedWords) {
    const cell = document.createElement("td");

    if (!placedWords.length) {
      cell.textContent = "-";
      return cell;
    }

    const details = document.createElement("details");
    const summary = document.createElement("summary");
    const list = document.createElement("div");

    details.className = "grid-words";
    summary.textContent = "Voir les mots";
    list.className = "grid-word-list";

    placedWords.forEach((entry) => {
      const item = document.createElement("div");
      const word = document.createElement("strong");
      const definition = document.createElement("span");
      const position = document.createElement("small");

      word.textContent = entry.word || "-";
      definition.textContent = getDefinitions(entry).join(" / ") || "-";
      position.textContent = formatWordPosition(entry);

      item.className = "grid-word-item";
      item.append(word, definition, position);
      list.append(item);
    });

    details.append(summary, list);
    cell.append(details);
    return cell;
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

  function formatWordPosition(entry) {
    const cell = entry.definitionCell || {};
    const direction = entry.direction || {};
    const axis = Number(direction.rowDelta || direction.startRowDelta) !== 0 ? "Vertical" : "Horizontal";
    const row = Number.isFinite(cell.row) ? cell.row + 1 : "-";
    const column = Number.isFinite(cell.column) ? cell.column + 1 : "-";
    return `${axis} - ligne ${row}, colonne ${column}`;
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

  function normalizeSearch(value) {
    return String(value || "")
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .trim();
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
    stop,
  };
})();
