const NotificationsView = (() => {
  let unsubscribe = null;
  let firestore = null;
  let functions = null;
  let viewLoaded = false;
  let viewLoadPromise = null;
  let addButton = null;
  let form = null;
  let titleInput = null;
  let bodyInput = null;
  let scheduledAtInput = null;
  let soundSelect = null;
  let badgeSelect = null;
  let expirationValueInput = null;
  let expirationUnitSelect = null;
  let cancelButton = null;
  let statusNode = null;
  let tableBody = null;
  let weeklyStatus = null;

  function init() {}

  async function start() {
    try {
      await ensureView();
      await ensureFirebase();
      bindEvents();
      renderWeeklyStatus();

      if (unsubscribe) return;

      setStatus("Chargement...");
      unsubscribe = firestore
        .collection("notificationLogs")
        .orderBy("createdAt", "desc")
        .limit(50)
        .onSnapshot(
          (snapshot) => {
            renderLogs(snapshot.docs);
            setStatus("");
          },
          (error) => {
            setStatus(error.message || "Impossible de charger les notifications.", "error");
          }
        );
    } catch (error) {
      resolveNodes();
      setStatus(error.message || "Impossible de charger la page notifications.", "error");
    }
  }

  function stop() {
    if (!unsubscribe) return;
    unsubscribe();
    unsubscribe = null;
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
    viewLoaded = true;
    resolveNodes();
  }

  async function loadView() {
    const panel = document.getElementById("notifications-panel");
    if (!panel) throw new Error("Panneau notifications introuvable.");

    const viewSrc = panel.dataset.viewSrc;
    if (viewSrc && !panel.innerHTML.trim()) {
      const response = await fetch(viewSrc, { cache: "no-store" });
      if (!response.ok) throw new Error("Vue notifications introuvable.");
      panel.innerHTML = await response.text();
    }
  }

  async function ensureFirebase() {
    const services = AuthGate.ensureFirebase();
    firestore = services.firestore;
    functions = functions || (firebase.functions ? firebase.app().functions("europe-west1") : null);

    if (!firestore || !functions) {
      throw new Error("Firebase indisponible.");
    }
  }

  function resolveNodes() {
    addButton = document.getElementById("add-notification-button");
    form = document.getElementById("notification-form");
    titleInput = document.getElementById("notification-title");
    bodyInput = document.getElementById("notification-body");
    scheduledAtInput = document.getElementById("notification-scheduled-at");
    soundSelect = document.getElementById("notification-sound");
    badgeSelect = document.getElementById("notification-badge");
    expirationValueInput = document.getElementById("notification-expiration-value");
    expirationUnitSelect = document.getElementById("notification-expiration-unit");
    cancelButton = document.getElementById("notification-cancel");
    statusNode = document.getElementById("notifications-status");
    tableBody = document.getElementById("notifications-table-body");
    weeklyStatus = document.getElementById("weekly-notification-status");
  }

  function bindEvents() {
    if (addButton && !addButton.dataset.bound) {
      addButton.addEventListener("click", toggleForm);
      addButton.dataset.bound = "true";
    }

    if (cancelButton && !cancelButton.dataset.bound) {
      cancelButton.addEventListener("click", hideForm);
      cancelButton.dataset.bound = "true";
    }

    if (form && !form.dataset.bound) {
      form.addEventListener("submit", submitNotification);
      form.dataset.bound = "true";
    }
  }

  function toggleForm() {
    if (!form) return;
    form.classList.toggle("is-hidden");
    addButton.textContent = form.classList.contains("is-hidden") ? "+" : "-";
  }

  function hideForm() {
    if (!form) return;
    form.classList.add("is-hidden");
    addButton.textContent = "+";
  }

  function setStatus(message, tone = "") {
    if (!statusNode) return;
    statusNode.textContent = message;
    statusNode.dataset.tone = tone;
  }

  function renderWeeklyStatus() {
    if (!weeklyStatus) return;
    weeklyStatus.textContent = "Activée";
  }

  async function submitNotification(event) {
    event.preventDefault();

    const body = String(bodyInput?.value || "").trim();
    const scheduledAt = String(scheduledAtInput?.value || "").trim();
    const sound = String(soundSelect?.value || "default");
    const badge = String(badgeSelect?.value || "1");
    const expirationValue = Number.parseInt(String(expirationValueInput?.value || "1"), 10);
    const expirationUnit = String(expirationUnitSelect?.value || "days");

    if (!body) {
      setStatus("Texte requis.", "error");
      return;
    }

    if (scheduledAt && !Number.isFinite(new Date(scheduledAt).getTime())) {
      setStatus("Date de programmation invalide.", "error");
      return;
    }

    if (!Number.isFinite(expirationValue) || expirationValue < 0) {
      setStatus("Délai d'expiration invalide.", "error");
      return;
    }

    const scheduledAtPayload = scheduledAt ? new Date(scheduledAt).toISOString() : "";

    const actionLabel = scheduledAt ? "Programmer cette notification ?" : "Envoyer cette notification maintenant ?";
    if (!window.confirm(actionLabel)) return;

    try {
      setStatus(scheduledAt ? "Programmation..." : "Envoi...");
      await functions.httpsCallable("sendAdminNotification")({
        body,
        scheduledAt: scheduledAtPayload,
        sound,
        badge,
        expiration: {
          value: expirationValue,
          unit: expirationUnit,
        },
      });
      form.reset();
      if (titleInput) titleInput.value = "Flèche-moi ça";
      if (soundSelect) soundSelect.value = "default";
      if (badgeSelect) badgeSelect.value = "1";
      if (expirationValueInput) expirationValueInput.value = "1";
      if (expirationUnitSelect) expirationUnitSelect.value = "days";
      hideForm();
      setStatus(scheduledAt ? "Notification programmée." : "Notification envoyée.");
    } catch (error) {
      setStatus(error.message || "Impossible d'envoyer la notification.", "error");
    }
  }

  function renderLogs(docs) {
    if (!tableBody) return;
    tableBody.replaceChildren();

    if (!docs.length) {
      const row = document.createElement("tr");
      const cell = document.createElement("td");
      cell.colSpan = 6;
      cell.className = "empty-cell";
      cell.textContent = "Aucune notification.";
      row.append(cell);
      tableBody.append(row);
      return;
    }

    const fragment = document.createDocumentFragment();
    docs.forEach((doc) => fragment.append(createLogRow(doc.id, doc.data())));
    tableBody.append(fragment);
  }

  function createLogRow(id, data) {
    const row = document.createElement("tr");
    row.append(
      makeTextCell(data.body || "-"),
      makeBadgeCell(data.status || "-"),
      makeTextCell(formatDelivery(data.delivery)),
      makeTextCell(formatValue(data.scheduledAt)),
      makeSentCell(id, data),
      makeDeleteCell(id, data)
    );
    return row;
  }

  function makeTextCell(value) {
    const cell = document.createElement("td");
    cell.textContent = value || "-";
    return cell;
  }

  function makeBadgeCell(value) {
    const cell = document.createElement("td");
    const badge = document.createElement("span");
    badge.className = "status-badge";
    const normalized = String(value || "").toLowerCase();
    if (normalized === "sent") badge.classList.add("status-badge-published");
    if (normalized === "scheduled") badge.classList.add("status-badge-scheduled");
    if (normalized === "cancelled") badge.classList.add("status-badge-blocked");
    if (normalized === "failed") badge.classList.add("status-badge-blocked");
      const statusLabels = {
        sent: "Envoyée",
        scheduled: "Programmée",
        cancelled: "Annulée",
        failed: "Échec"
      };

      badge.textContent = statusLabels[normalized] ?? value ?? "-";
    cell.append(badge);
    return cell;
  }

  function makeSentCell(id, data) {
    const normalizedStatus = String(data.status || "").toLowerCase();
    if (normalizedStatus !== "scheduled") {
      return makeTextCell(formatValue(data.sentAt));
    }

    const cell = document.createElement("td");
    const button = document.createElement("button");
    button.className = "ghost-button compact-action-button";
    button.type = "button";
    button.textContent = "Annuler";
    button.addEventListener("click", () => cancelScheduledNotification(id));
    cell.append(button);
    return cell;
  }

  function makeDeleteCell(id, data) {
    const cell = document.createElement("td");
    const button = document.createElement("button");
    button.className = "ghost-button compact-action-button danger-action-button";
    button.type = "button";
    button.textContent = "Supprimer";
    button.addEventListener("click", () => deleteNotification(id, data));
    cell.append(button);
    return cell;
  }

  async function cancelScheduledNotification(notificationID) {
    if (!notificationID) return;
    if (!window.confirm("Annuler cette notification programmée ?")) return;

    try {
      setStatus("Annulation...");
      await functions.httpsCallable("cancelAdminNotification")({ notificationID });
      setStatus("Notification annulée.");
    } catch (error) {
      setStatus(error.message || "Impossible d'annuler la notification.", "error");
    }
  }

  async function deleteNotification(notificationID, data = {}) {
    if (!notificationID) return;

    const normalizedStatus = String(data.status || "").toLowerCase();
    const confirmMessage =
      normalizedStatus === "scheduled"
        ? "Supprimer cette notification programmée ? Elle ne sera jamais envoyée."
        : "Supprimer cette notification de l'historique ?";

    if (!window.confirm(confirmMessage)) return;

    try {
      setStatus("Suppression...");
      await functions.httpsCallable("deleteAdminNotification")({ notificationID });
      setStatus("Notification supprimée.");
    } catch (error) {
      setStatus(error.message || "Impossible de supprimer la notification.", "error");
    }
  }

  function formatDelivery(delivery) {
    if (!delivery) return "-";

    const successCount = Number(delivery.successCount || 0);
    const tokenCount = Number(delivery.tokenCount || 0);
    const failureCount = Number(delivery.failureCount || 0);
    const suffix = failureCount > 0 ? `, ${failureCount} échec(s)` : "";
    return `${successCount}/${tokenCount}${suffix}`;
  }

  function formatValue(value) {
    if (!value) return "-";

    if (value.toDate) {
      return new Intl.DateTimeFormat("fr-FR", {
        dateStyle: "short",
        timeStyle: "short",
      }).format(value.toDate());
    }

    return String(value);
  }

  return {
    init,
    start,
    stop,
  };
})();
