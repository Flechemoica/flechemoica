const CommunicationsView = (() => {
  let firestore = null;
  let storage = null;
  let unsubscribeConfig = null;
  let unsubscribeCommunications = null;
  let viewLoaded = false;
  let viewLoadPromise = null;
  let communications = [];
  let activeCommunicationIDs = new Set();
  let isEnabled = true;

  let statusNode = null;
  let addButton = null;
  let form = null;
  let cancelButton = null;
  let textInput = null;
  let imageInput = null;
  let imageDropZone = null;
  let imageStatus = null;
  let enabledInput = null;
  let saveConfigButton = null;
  let listNode = null;

  function init() {
    resolveNodes();
  }

  async function start() {
    try {
      await ensureView();
      ensureFirebase();
      startListeners();
    } catch (error) {
      resolveNodes();
      setStatus(error.message || "Impossible de charger les communications.", "error");
    }
  }

  function stop() {
    if (unsubscribeConfig) {
      unsubscribeConfig();
      unsubscribeConfig = null;
    }

    if (unsubscribeCommunications) {
      unsubscribeCommunications();
      unsubscribeCommunications = null;
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
    viewLoaded = true;
    resolveNodes();
  }

  async function loadView() {
    const panel = document.getElementById("communications-panel");
    if (!panel) throw new Error("Panneau communications introuvable.");

    const viewSrc = panel.dataset.viewSrc;
    if (viewSrc && !panel.innerHTML.trim()) {
      const response = await fetch(viewSrc, { cache: "no-store" });
      if (!response.ok) throw new Error("Vue communications introuvable.");
      panel.innerHTML = await response.text();
    }
  }

  function ensureFirebase() {
    AuthGate.ensureFirebase();
    firestore = firestore || firebase.firestore();

    if (!firebase.storage) {
      throw new Error("Firebase Storage n'est pas charge dans l'administration.");
    }

    storage = storage || firebase.storage();
  }

  function resolveNodes() {
    statusNode = document.getElementById("communications-status");
    addButton = document.getElementById("add-communication-button");
    form = document.getElementById("communication-form");
    cancelButton = document.getElementById("communication-cancel-button");
    textInput = document.getElementById("communication-text");
    imageInput = document.getElementById("communication-image");
    imageDropZone = document.getElementById("communication-image-drop-zone");
    imageStatus = document.getElementById("communication-image-status");
    enabledInput = document.getElementById("communication-enabled");
    saveConfigButton = document.getElementById("save-communication-config-button");
    listNode = document.getElementById("communications-list");

    if (addButton && !addButton.dataset.bound) {
      addButton.addEventListener("click", showForm);
      addButton.dataset.bound = "true";
    }

    if (cancelButton && !cancelButton.dataset.bound) {
      cancelButton.addEventListener("click", hideForm);
      cancelButton.dataset.bound = "true";
    }

    if (form && !form.dataset.bound) {
      form.addEventListener("submit", createCommunication);
      form.dataset.bound = "true";
    }

    if (saveConfigButton && !saveConfigButton.dataset.bound) {
      saveConfigButton.addEventListener("click", saveConfig);
      saveConfigButton.dataset.bound = "true";
    }

    if (imageInput && !imageInput.dataset.bound) {
      imageInput.addEventListener("change", updateImageStatus);
      imageInput.dataset.bound = "true";
    }

    if (imageDropZone && !imageDropZone.dataset.bound) {
      imageDropZone.addEventListener("click", () => imageInput?.click());
      imageDropZone.addEventListener("keydown", (event) => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          imageInput?.click();
        }
      });
      imageDropZone.addEventListener("dragover", handleImageDragOver);
      imageDropZone.addEventListener("dragleave", handleImageDragLeave);
      imageDropZone.addEventListener("drop", handleImageDrop);
      imageDropZone.dataset.bound = "true";
    }
  }

  function startListeners() {
    if (!unsubscribeConfig) {
      unsubscribeConfig = firestore
        .collection("appConfiguration")
        .doc("homeCommunication")
        .onSnapshot(
          (doc) => {
            const data = doc.exists ? doc.data() : {};
            isEnabled = data.isEnabled !== false;
            activeCommunicationIDs = new Set(Array.isArray(data.activeCommunicationIDs) ? data.activeCommunicationIDs : []);
            renderConfig();
            renderCommunications();
          },
          (error) => setStatus(error.message || "Impossible de charger la configuration.", "error")
        );
    }

    if (!unsubscribeCommunications) {
      unsubscribeCommunications = firestore
        .collection("homeCommunications")
        .orderBy("createdAt", "desc")
        .limit(50)
        .onSnapshot(
          (snapshot) => {
            communications = snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
            renderCommunications();
            setStatus("");
          },
          (error) => setStatus(error.message || "Impossible de charger les communications.", "error")
        );
    }
  }

  function renderConfig() {
    if (enabledInput) {
      enabledInput.checked = isEnabled;
    }
  }

  function renderCommunications() {
    if (!listNode) return;

    if (!communications.length) {
      listNode.innerHTML = '<div class="notification-card"><h3>Aucune communication</h3></div>';
      return;
    }

    listNode.innerHTML = communications.map((communication) => {
      const checked = activeCommunicationIDs.has(communication.id) ? "checked" : "";
      const text = escapeHTML(communication.text || "");
      const image = communication.imageURL
        ? `<img class="communication-thumb" src="${escapeAttribute(communication.imageURL)}" alt="">`
        : `<div class="communication-thumb communication-thumb-empty">Texte</div>`;
      const createdAt = formatDate(communication.createdAt);

      return `
        <article class="communication-card">
          ${image}
          <div class="communication-card-body">
            <div class="communication-card-header">
              <label class="switch-row">
                <input type="checkbox" data-communication-active="${escapeAttribute(communication.id)}" ${checked}>
                <span>Active dans le bloc</span>
              </label>
              <span class="status-badge">${createdAt}</span>
            </div>
            <p>${text || "Image sans texte"}</p>
          </div>
        </article>
      `;
    }).join("");

    listNode.querySelectorAll("[data-communication-active]").forEach((input) => {
      input.addEventListener("change", () => {
        const id = input.dataset.communicationActive;
        if (input.checked) {
          activeCommunicationIDs.add(id);
        } else {
          activeCommunicationIDs.delete(id);
        }
      });
    });
  }

  function showForm() {
    form?.classList.remove("is-hidden");
    textInput?.focus();
  }

  function hideForm() {
    form?.classList.add("is-hidden");
    form?.reset();
    updateImageStatus();
  }

  async function createCommunication(event) {
    event.preventDefault();

    const text = (textInput?.value || "").trim();
    const file = imageInput?.files?.[0] || null;

    if (!text && !file) {
      setStatus("Ajoute une image ou un texte.", "error");
      return;
    }

    if (file && !file.type.startsWith("image/")) {
      setStatus("Le fichier choisi doit être une image.", "error");
      return;
    }

    setStatus("Création...");
    setFormDisabled(true);

    try {
      const documentRef = firestore.collection("homeCommunications").doc();
      const payload = {
        text,
        createdBy: firebase.auth().currentUser?.uid || "",
        createdAt: firebase.firestore.FieldValue.serverTimestamp(),
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      };

      if (file) {
        const storagePath = `homeCommunications/${documentRef.id}/${sanitizeFileName(file.name)}`;
        const imageRef = storage.ref().child(storagePath);
        const snapshot = await imageRef.put(file, { contentType: file.type || "image/jpeg" });
        payload.imageURL = await snapshot.ref.getDownloadURL();
        payload.storagePath = storagePath;
      }

      await documentRef.set(payload);
      activeCommunicationIDs.add(documentRef.id);
      await persistConfig();
      hideForm();
      setStatus("Communication créée.");
    } catch (error) {
      setStatus(error.message || "Impossible de créer la communication.", "error");
    } finally {
      setFormDisabled(false);
    }
  }

  async function saveConfig() {
    isEnabled = Boolean(enabledInput?.checked);
    setStatus("Enregistrement...");

    try {
      await persistConfig();
      setStatus("Affichage enregistré.");
    } catch (error) {
      setStatus(error.message || "Impossible d'enregistrer l'affichage.", "error");
    }
  }

  function persistConfig() {
    return firestore.collection("appConfiguration").doc("homeCommunication").set({
      isEnabled,
      activeCommunicationIDs: Array.from(activeCommunicationIDs),
      updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }

  function setFormDisabled(isDisabled) {
    form?.querySelectorAll("button, input, textarea").forEach((node) => {
      node.disabled = isDisabled;
    });
  }

  function updateImageStatus() {
    if (!imageStatus) return;
    const file = imageInput?.files?.[0];
    imageStatus.textContent = file ? file.name : "Image optionnelle. Format conseillé: le ratio du bloc affiché dans l'app.";
  }

  function handleImageDragOver(event) {
    event.preventDefault();
    imageDropZone?.classList.add("is-dragging");
  }

  function handleImageDragLeave(event) {
    event.preventDefault();
    imageDropZone?.classList.remove("is-dragging");
  }

  function handleImageDrop(event) {
    event.preventDefault();
    imageDropZone?.classList.remove("is-dragging");
    const file = event.dataTransfer?.files?.[0];
    if (!file || !imageInput) return;

    const dataTransfer = new DataTransfer();
    dataTransfer.items.add(file);
    imageInput.files = dataTransfer.files;
    updateImageStatus();
  }

  function setStatus(message, tone = "") {
    if (!statusNode) return;
    statusNode.textContent = message;
    statusNode.dataset.tone = tone;
  }

  function formatDate(timestamp) {
    const date = timestamp?.toDate ? timestamp.toDate() : null;
    if (!date) return "Nouveau";
    return new Intl.DateTimeFormat("fr-FR", { dateStyle: "short", timeStyle: "short" }).format(date);
  }

  function sanitizeFileName(name) {
    return String(name || "image.jpg")
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[^a-zA-Z0-9._-]/g, "-")
      .toLowerCase();
  }

  function escapeHTML(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  function escapeAttribute(value) {
    return escapeHTML(value).replace(/`/g, "&#096;");
  }

  return {
    init,
    start,
    stop,
  };
})();
