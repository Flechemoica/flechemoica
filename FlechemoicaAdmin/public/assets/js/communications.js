const CommunicationsView = (() => {
  const admobCommunicationID = "admobCommunication";
  const admobCommunication = {
    id: admobCommunicationID,
    title: "Publicité AdMob",
    type: "ad",
    text: "Publicité AdMob",
    isSystem: true,
  };
  const unityCommunicationID = "unityCommunication";
  const unityCommunication = {
    id: unityCommunicationID,
    title: "Publicité Unity Ads",
    type: "unityAd",
    text: "Publicité Unity Ads",
    isSystem: true,
  };
  const classicBlockHeightPX = 500;
  const defaultAdmobBannerMaxHeight = 100;
  const defaultUnityBannerMaxHeight = 100;

  let firestore = null;
  let storage = null;
  let functions = null;
  let unsubscribeConfig = null;
  let unsubscribeCommunications = null;
  let viewLoaded = false;
  let viewLoadPromise = null;
  let communications = [];
  let pollResults = new Map();
  let activeCommunicationIDs = new Set();
  let communicationPositions = {};
  let isEnabled = true;
  let blockHeightPX = classicBlockHeightPX;
  let admobBannerMaxHeight = defaultAdmobBannerMaxHeight;
  let unityBannerMaxHeight = defaultUnityBannerMaxHeight;
  let editingCommunicationID = "";

  let statusNode = null;
  let addButton = null;
  let form = null;
  let submitButton = null;
  let cancelButton = null;
  let typeInput = null;
  let typeChoiceInputs = [];
  let titleInput = null;
  let testModeInput = null;
  let textInput = null;
  let textGroup = null;
  let imageGroup = null;
  let imageOverlayTextInput = null;
  let imageOverlayTextGroup = null;
  let pollBuilder = null;
  let pollQuestionInput = null;
  let pollOptionsList = null;
  let addPollOptionButton = null;
  let imageInput = null;
  let imageDropZone = null;
  let imageStatus = null;
  let sponsoredGroup = null;
  let clientNameInput = null;
  let destinationURLInput = null;
  let invoiceNumberInput = null;
  let periodsBuilder = null;
  let periodsList = null;
  let addPeriodButton = null;
  let enabledInput = null;
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
    functions = functions || (firebase.functions ? firebase.app().functions("europe-west1") : null);
  }

  function resolveNodes() {
    statusNode = document.getElementById("communications-status");
    addButton = document.getElementById("add-communication-button");
    form = document.getElementById("communication-form");
    submitButton = document.getElementById("communication-submit-button");
    cancelButton = document.getElementById("communication-cancel-button");
    typeInput = document.getElementById("communication-type");
    typeChoiceInputs = Array.from(document.querySelectorAll("[name='communication-type-choice']"));
    titleInput = document.getElementById("communication-title");
    testModeInput = document.getElementById("communication-test-mode");
    textInput = document.getElementById("communication-text");
    textGroup = document.getElementById("communication-text-group");
    imageGroup = document.getElementById("communication-image-group");
    imageOverlayTextInput = document.getElementById("communication-image-overlay-text");
    imageOverlayTextGroup = document.getElementById("communication-image-overlay-group");
    pollBuilder = document.getElementById("communication-poll-builder");
    pollQuestionInput = document.getElementById("communication-poll-question");
    pollOptionsList = document.getElementById("communication-poll-options-list");
    addPollOptionButton = document.getElementById("communication-add-poll-option");
    imageInput = document.getElementById("communication-image");
    imageDropZone = document.getElementById("communication-image-drop-zone");
    imageStatus = document.getElementById("communication-image-status");
    sponsoredGroup = document.getElementById("communication-sponsored-group");
    clientNameInput = document.getElementById("communication-client-name");
    destinationURLInput = document.getElementById("communication-destination-url");
    invoiceNumberInput = document.getElementById("communication-invoice-number");
    periodsBuilder = document.getElementById("communication-periods-builder");
    periodsList = document.getElementById("communication-periods-list");
    addPeriodButton = document.getElementById("communication-add-period");
    enabledInput = document.getElementById("communication-enabled");
    listNode = document.getElementById("communications-list");

    if (addButton && !addButton.dataset.bound) {
      addButton.addEventListener("click", (event) => {
        event.preventDefault();
        showForm();
      });
      addButton.dataset.bound = "true";
    }

    if (listNode && !listNode.dataset.actionsBound) {
      listNode.addEventListener("click", (event) => {
        const editButton = event.target.closest("[data-edit-communication]");
        if (editButton) {
          event.preventDefault();
          editCommunication(editButton.dataset.editCommunication);
          return;
        }

        const deleteButton = event.target.closest("[data-delete-communication]");
        if (deleteButton) {
          event.preventDefault();
          deleteCommunication(deleteButton.dataset.deleteCommunication);
          return;
        }
        const reportButton = event.target.closest("[data-report-communication]");
        if (reportButton) {
          event.preventDefault();
          generateSponsoredReport(reportButton.dataset.reportCommunication);
        }
      });
      listNode.dataset.actionsBound = "true";
    }

    if (cancelButton && !cancelButton.dataset.bound) {
      cancelButton.addEventListener("click", hideForm);
      cancelButton.dataset.bound = "true";
    }

    if (form && !form.dataset.bound) {
      form.addEventListener("submit", saveCommunication);
      form.dataset.bound = "true";
    }

    if (typeInput && !typeInput.dataset.bound) {
      typeInput.addEventListener("change", updateFormForType);
      typeInput.dataset.bound = "true";
    }

    if (testModeInput && !testModeInput.dataset.bound) {
      testModeInput.addEventListener("change", updateFormForType);
      testModeInput.dataset.bound = "true";
    }

    typeChoiceInputs.forEach((input) => {
      if (input.dataset.bound) return;
      input.addEventListener("change", () => {
        if (!input.checked) return;
        setCommunicationType(input.value);
      });
      input.dataset.bound = "true";
    });

    if (addPollOptionButton && !addPollOptionButton.dataset.bound) {
      addPollOptionButton.addEventListener("click", () => addPollOptionInput(""));
      addPollOptionButton.dataset.bound = "true";
    }

    if (addPeriodButton && !addPeriodButton.dataset.bound) {
      addPeriodButton.addEventListener("click", () => addPeriodRow());
      addPeriodButton.dataset.bound = "true";
    }

    if (enabledInput && !enabledInput.dataset.bound) {
      enabledInput.addEventListener("change", saveConfig);
      enabledInput.dataset.bound = "true";
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
            communicationPositions = data.communicationPositions || {};
            blockHeightPX = normalizeBlockHeight(data.blockHeightPX);
            admobBannerMaxHeight = normalizeAdmobBannerMaxHeight(data.admobBannerMaxHeight);
            unityBannerMaxHeight = normalizeUnityBannerMaxHeight(data.unityBannerMaxHeight);
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
    const now = new Date();
    const scheduledFutureIDs = new Set(communications
      .filter((communication) => {
        const periods = communicationPeriods(communication);
        const isCurrent = periods.some((period) =>
          period.startsAt && period.endsAt && period.startsAt <= now && now < period.endsAt
        );
        const hasFuture = periods.some((period) =>
          period.startsAt && period.endsAt && now < period.startsAt && period.startsAt < period.endsAt
        );
        return !isCurrent && hasFuture;
      })
      .map((communication) => communication.id));
    const configuredPrimaryID = Array.from(activeCommunicationIDs).find((id) =>
      id === admobCommunicationID
      || id === unityCommunicationID
      || communications.find((communication) => communication.id === id)?.isTestMode !== true
    );
    const usesAdmobUntilScheduledStart = configuredPrimaryID && scheduledFutureIDs.has(configuredPrimaryID);

    const renderedCommunications = [admobCommunication, unityCommunication, ...communications].sort((first, second) => {
      const firstActive = activeCommunicationIDs.has(first.id) ? 1 : 0;
      const secondActive = activeCommunicationIDs.has(second.id) ? 1 : 0;
      if (firstActive !== secondActive) return secondActive - firstActive;
      if (first.isSystem && !second.isSystem) return -1;
      if (!first.isSystem && second.isSystem) return 1;
      return 0;
    });

    if (!renderedCommunications.length) {
      listNode.innerHTML = '<div class="notification-card"><h3>Aucune communication</h3></div>';
      return;
    }

    listNode.innerHTML = renderedCommunications.map((communication) => {
      const periods = communicationPeriods(communication);
      const isCurrentlyScheduled = periods.some((period) =>
        period.startsAt && period.endsAt && period.startsAt <= now && now < period.endsAt
      );
      const hasFuturePeriod = periods.some((period) =>
        period.startsAt && period.endsAt && now < period.startsAt && period.startsAt < period.endsAt
      );
      const isScheduled = !isCurrentlyScheduled && hasFuturePeriod;
      const isEffectivelyActive = activeCommunicationIDs.has(communication.id)
        || (communication.id === admobCommunicationID && usesAdmobUntilScheduledStart);
      const checked = !isScheduled && isEffectivelyActive ? "checked" : "";
      const disabled = isScheduled ? "disabled" : "";
      const state = isScheduled ? "scheduled" : (checked ? "active" : "inactive");
      const toggleLabel = isScheduled
        ? "Communication programmée — modification depuis le formulaire uniquement"
        : "Activer cette communication";
      const type = getCommunicationType(communication);
      const preview = renderCommunicationPreview(communication, type);
      const title = getCommunicationTitle(communication, type);
      const testBadge = communication.isTestMode === true
        ? '<span class="communication-test-badge">TEST · EDITORS</span>'
        : "";
      const scheduleSummary = communication.isSystem || type.value === "sponsored"
        ? ""
        : renderScheduleSummary(communication);
      const position = Number(communication.position || communicationPositions[communication.id] || 2);
      const actions = communication.isSystem || type.value === "ad"
        ? ""
        : `
            ${type.value === "sponsored" ? `<button class="icon-action-button report-action-button" type="button" data-report-communication="${escapeAttribute(communication.id)}" aria-label="Créer le rapport PDF" title="Créer le rapport PDF">Rapport</button>` : ""}
            <button class="icon-action-button" type="button" data-edit-communication="${escapeAttribute(communication.id)}" aria-label="Modifier">
              <span aria-hidden="true">✎</span>
            </button>
            <button class="icon-action-button danger-button" type="button" data-delete-communication="${escapeAttribute(communication.id)}" aria-label="Supprimer">
              <span aria-hidden="true">×</span>
            </button>
          `;
      const admobHeightControl = communication.id === admobCommunicationID
        ? `
            <label class="admob-height-control">
              <span>Hauteur max</span>
              <input type="number" min="50" max="300" step="5" value="${admobBannerMaxHeight}" data-admob-banner-max-height>
              <span>pt</span>
            </label>
          `
        : "";
      const unityHeightControl = communication.id === unityCommunicationID
        ? `
            <label class="admob-height-control">
              <span>Hauteur max</span>
              <input type="number" min="50" max="300" step="5" value="${unityBannerMaxHeight}" data-unity-banner-max-height>
              <span>pt</span>
            </label>
          `
        : "";

      return `
        <article class="communication-card" data-communication-state="${state}">
          <div class="communication-card-heading">
            <h3 class="communication-card-title">${escapeHTML(title)}</h3>
            ${testBadge}
          </div>
          ${preview}
          <div class="communication-card-footer">
            <label class="communication-toggle" data-state="${state}" for="communication-card-${escapeAttribute(communication.id)}" aria-label="${toggleLabel}" title="${toggleLabel}">
              <input id="communication-card-${escapeAttribute(communication.id)}" type="checkbox" data-communication-active="${escapeAttribute(communication.id)}" ${checked} ${disabled}>
              <span></span>
            </label>
            <button class="communication-position-toggle" type="button" data-communication-position="${escapeAttribute(communication.id)}" data-position="${position}" aria-label="Position ${position} du bloc" title="Cliquer pour changer la position">
              <span>${position}</span>
            </button>
            ${scheduleSummary}
            ${admobHeightControl}
            ${unityHeightControl}
            <div class="communication-card-actions">${actions}</div>
          </div>
        </article>
      `;
    }).join("");

    listNode.querySelectorAll("[data-communication-active]").forEach((input) => {
      input.addEventListener("change", () => {
        const id = input.dataset.communicationActive;
        const selectedCommunication = communications.find((communication) => communication.id === id);
        const isTestCommunication = selectedCommunication?.isTestMode === true;
        const activeTestIDs = communications
          .filter((communication) => communication.isTestMode === true && activeCommunicationIDs.has(communication.id))
          .map((communication) => communication.id);
        const now = new Date();
        const reservedAdvertisement = communications.find((communication) =>
          getCommunicationType(communication).value === "sponsored"
          && communicationPeriods(communication).some((period) =>
            period.startsAt <= now && now < period.endsAt
          )
        );
        if (!isTestCommunication && reservedAdvertisement && (id !== reservedAdvertisement.id || !input.checked)) {
          activeCommunicationIDs = new Set([reservedAdvertisement.id, ...activeTestIDs]);
          setStatus("Impossible : cette période est réservée à une publicité client.", "error");
          renderCommunications();
          return;
        }
        if (input.checked) {
          activeCommunicationIDs = isTestCommunication
            ? new Set([...activeCommunicationIDs, id])
            : new Set([id, ...activeTestIDs]);
          isEnabled = true;
          if (id !== admobCommunicationID && id !== unityCommunicationID) {
            blockHeightPX = classicBlockHeightPX;
          }
          if (enabledInput) enabledInput.checked = true;
        } else {
          if (isTestCommunication) {
            activeCommunicationIDs.delete(id);
            if (activeCommunicationIDs.size === 0) activeCommunicationIDs.add(admobCommunicationID);
          } else {
            activeCommunicationIDs = new Set([admobCommunicationID, ...activeTestIDs]);
          }
          isEnabled = true;
          blockHeightPX = classicBlockHeightPX;
          if (enabledInput) enabledInput.checked = true;
        }
        persistConfig()
          .then(renderCommunications)
          .catch((error) => {
            setStatus(error.message || "Impossible d'enregistrer l'affichage.", "error");
          });
      });
    });

    listNode.querySelectorAll("[data-communication-position]").forEach((button) => {
      button.addEventListener("click", async () => {
        const id = button.dataset.communicationPosition;
        const currentPosition = Math.max(1, Math.min(3, Number(button.dataset.position) || 2));
        const position = currentPosition === 3 ? 1 : currentPosition + 1;
        try {
          if (id === admobCommunicationID || id === unityCommunicationID) {
            communicationPositions[id] = position;
            await persistConfig();
          } else {
            await firestore.collection("homeCommunications").doc(id).set({ position }, { merge: true });
            const communication = communications.find((item) => item.id === id);
            if (communication) communication.position = position;
          }
          button.dataset.position = String(position);
          button.setAttribute("aria-label", `Position ${position} du bloc`);
          const label = button.querySelector("span");
          if (label) label.textContent = String(position);
          setStatus("");
        } catch (error) {
          setStatus(error.message || "Impossible d’enregistrer la position.", "error");
        }
      });
    });

    listNode.querySelectorAll("[data-admob-banner-max-height]").forEach((input) => {
      input.addEventListener("change", async () => {
        admobBannerMaxHeight = normalizeAdmobBannerMaxHeight(input.value);
        input.value = String(admobBannerMaxHeight);
        try {
          await persistConfig();
          setStatus("Hauteur maximale AdMob enregistrée.");
        } catch (error) {
          setStatus(error.message || "Impossible d’enregistrer la hauteur AdMob.", "error");
        }
      });
    });

    listNode.querySelectorAll("[data-unity-banner-max-height]").forEach((input) => {
      input.addEventListener("change", async () => {
        unityBannerMaxHeight = normalizeUnityBannerMaxHeight(input.value);
        input.value = String(unityBannerMaxHeight);
        try {
          await persistConfig();
          setStatus("Hauteur maximale Unity Ads enregistrée.");
        } catch (error) {
          setStatus(error.message || "Impossible d’enregistrer la hauteur Unity Ads.", "error");
        }
      });
    });

    loadVisiblePollResults(renderedCommunications);
  }

  function showForm() {
    editingCommunicationID = "";
    form?.reset();
    setCommunicationType("text", { focus: false });
    renderPollOptions(["", ""], { focus: false });
    renderPeriods([]);
    if (submitButton) submitButton.textContent = "Créer la communication";
    form?.classList.remove("is-hidden");
    updateFormForType();
    textInput?.focus();
  }

  function hideForm() {
    form?.classList.add("is-hidden");
    form?.reset();
    editingCommunicationID = "";
    setCommunicationType("text", { focus: false });
    renderPollOptions(["", ""], { focus: false });
    renderPeriods([]);
    if (submitButton) submitButton.textContent = "Créer la communication";
    updateImageStatus();
  }

  function editCommunication(id) {
    const communication = communications.find((item) => item.id === id);
    if (!communication) return;

    editingCommunicationID = id;
    const type = getCommunicationType(communication).value;
    setCommunicationType(type, { focus: false });
    if (textInput) textInput.value = communication.text || "";
    if (imageOverlayTextInput) imageOverlayTextInput.value = communication.imageOverlayText || "";
    if (titleInput) titleInput.value = getCommunicationTitle(communication, { value: type });
    if (testModeInput) testModeInput.checked = communication.isTestMode === true;
    const storedPeriods = Array.isArray(communication.displayPeriods) && communication.displayPeriods.length
      ? communication.displayPeriods
      : (communication.startsAt || communication.endsAt
          ? [{ startsAt: communication.startsAt, endsAt: communication.endsAt }]
          : []);
    renderPeriods(storedPeriods);
    if (clientNameInput) clientNameInput.value = communication.clientName || "";
    if (destinationURLInput) {
      destinationURLInput.value = communication.originalDestinationURL || communication.destinationURL || "";
    }
    if (invoiceNumberInput) invoiceNumberInput.value = communication.invoiceNumber || "";
    if (pollQuestionInput) pollQuestionInput.value = communication.text || "";
    renderPollOptions(Array.isArray(communication.pollOptions) ? communication.pollOptions : ["", ""], { focus: false });
    if (imageInput) imageInput.value = "";
    if (submitButton) submitButton.textContent = "Enregistrer la communication";
    form?.classList.remove("is-hidden");
    updateFormForType();
    updateImageStatus();
    textInput?.focus();
  }

  async function saveCommunication(event) {
    event.preventDefault();

    const wasEditing = Boolean(editingCommunicationID);
    const existingCommunication = wasEditing
      ? communications.find((item) => item.id === editingCommunicationID)
      : null;
    const type = typeInput?.value || "text";
    const enteredTitle = (titleInput?.value || "").trim();
    const isTestMode = testModeInput?.checked === true;
    const isTestSponsored = type === "sponsored" && isTestMode;
    const displayPeriods = isTestSponsored ? [] : readDisplayPeriods();
    const clientName = (clientNameInput?.value || "").trim();
    const title = type === "sponsored" ? `Annonce ${clientName}`.trim() : enteredTitle;
    const destinationURL = (destinationURLInput?.value || "").trim();
    const invoiceNumber = (invoiceNumberInput?.value || "").trim();
    const imageOverlayText = type === "image" ? (imageOverlayTextInput?.value || "").trim() : "";
    const text = type === "image" || type === "sponsored"
      ? ""
      : type === "poll"
      ? (pollQuestionInput?.value || "").trim()
      : (textInput?.value || "").trim();
    const pollOptions = readPollOptions();
    const file = imageInput?.files?.[0] || null;

    if (!title) {
      setStatus("Ajoute un titre.", "error");
      return;
    }

    if (displayPeriods.some((period) => !period.startsAt || !period.endsAt || period.startsAt >= period.endsAt)) {
      setStatus("Chaque période doit avoir un début et une fin valides.", "error");
      return;
    }

    if (hasExclusiveScheduleConflict(type, displayPeriods, editingCommunicationID)) {
      setStatus("Créneau indisponible : une publicité client réserve déjà tout ou partie de cette période.", "error");
      return;
    }

    if (type === "text" && !text) {
      setStatus("Ajoute un texte.", "error");
      return;
    }

    if (type === "image" && !file && !existingCommunication?.imageURL) {
      setStatus("Ajoute une image 1077 x 500 px.", "error");
      return;
    }

    if (type === "sponsored" && (!clientName || !destinationURL || (!file && !existingCommunication?.imageURL))) {
      setStatus("Ajoute le nom du client, un lien HTTPS et une image.", "error");
      return;
    }

    if (type === "sponsored" && !/^https:\/\//i.test(destinationURL)) {
      setStatus("La publicité client exige un lien HTTPS.", "error");
      return;
    }

    if (type === "sponsored" && !isTestMode && displayPeriods.length === 0) {
      setStatus("La publicité client exige au moins une période hors mode test.", "error");
      return;
    }

    if (type === "poll" && (!text || pollOptions.length < 2)) {
      setStatus("Ajoute une question et au moins 2 choix.", "error");
      return;
    }

    if ((type === "image" || type === "sponsored" || file) && file
        && !file.type.startsWith("image/") && !file.type.startsWith("video/")) {
      setStatus("Le fichier choisi doit être une image, un GIF ou une vidéo.", "error");
      return;
    }

    let imageDimensions = null;
    if ((type === "image" || type === "sponsored") && file) {
      imageDimensions = await readMediaDimensions(file);
      const dimensions = imageDimensions;
      if (!file.type.startsWith("video/") && (dimensions.width !== 1077 || dimensions.height !== 500)) {
        if (type === "image" || dimensions.width !== 1077) {
          const expected = type === "sponsored" ? "largeur attendue : 1077 px" : "format attendu : 1077 x 500 px";
          setStatus(`Image ${dimensions.width} x ${dimensions.height} px. ${expected}.`, "error");
          return;
        }
      }
    }

    setStatus(wasEditing ? "Enregistrement..." : "Création...");
    setFormDisabled(true);

    try {
      const documentRef = wasEditing
        ? firestore.collection("homeCommunications").doc(editingCommunicationID)
        : firestore.collection("homeCommunications").doc();
      let uploadedImage = null;
      if (file) {
        if (type === "sponsored") {
          uploadedImage = await uploadSponsoredImage(documentRef.id, file);
        } else {
          const storagePath = `homeCommunications/${documentRef.id}/${sanitizeFileName(file.name)}`;
          const imageRef = storage.ref().child(storagePath);
          const snapshot = await imageRef.put(file, { contentType: file.type || "image/jpeg" });
          uploadedImage = {
            imageURL: await snapshot.ref.getDownloadURL(),
            storagePath,
            storageProvider: "firebase",
          };
        }
      }
      const payload = {
        title,
        isTestMode,
        type,
        text,
        clientName: type === "sponsored" ? clientName : firebase.firestore.FieldValue.delete(),
        destinationURL: type === "sponsored" ? destinationURL : firebase.firestore.FieldValue.delete(),
        invoiceNumber: type === "sponsored" && invoiceNumber ? invoiceNumber : firebase.firestore.FieldValue.delete(),
        originalDestinationURL: firebase.firestore.FieldValue.delete(),
        imageOverlayText,
        mediaKind: type === "image" || type === "sponsored"
          ? getMediaKind(file?.type || existingCommunication?.mediaType || "")
          : firebase.firestore.FieldValue.delete(),
        mediaType: type === "image" || type === "sponsored"
          ? (file?.type || existingCommunication?.mediaType || "image/jpeg")
          : firebase.firestore.FieldValue.delete(),
        pollOptions: type === "poll" ? pollOptions : [],
        displayPeriods: displayPeriods.map((period) => ({
          startsAt: firebase.firestore.Timestamp.fromDate(period.startsAt),
          endsAt: firebase.firestore.Timestamp.fromDate(period.endsAt),
        })),
        position: Number(existingCommunication?.position || 2),
        startsAt: firebase.firestore.FieldValue.delete(),
        endsAt: firebase.firestore.FieldValue.delete(),
        updatedBy: firebase.auth().currentUser?.uid || "",
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      };

      if (!wasEditing) {
        payload.createdBy = firebase.auth().currentUser?.uid || "";
        payload.createdAt = firebase.firestore.FieldValue.serverTimestamp();
      }

      await documentRef.set(payload, { merge: true });

      if (uploadedImage) {
        await documentRef.set({
          imageURL: uploadedImage.imageURL,
          storagePath: uploadedImage.storagePath,
          storageProvider: uploadedImage.storageProvider,
          imageWidth: imageDimensions?.width || firebase.firestore.FieldValue.delete(),
          imageHeight: imageDimensions?.height || firebase.firestore.FieldValue.delete(),
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      } else if (type !== "image" && type !== "sponsored") {
        await documentRef.set({
          imageURL: firebase.firestore.FieldValue.delete(),
          imageDataBase64: firebase.firestore.FieldValue.delete(),
          imageOverlayText: firebase.firestore.FieldValue.delete(),
          storagePath: firebase.firestore.FieldValue.delete(),
        }, { merge: true });
      }

      if (type !== "poll") {
        await deleteExistingPollVotes(documentRef.id);
      }
      if (isTestMode) {
        activeCommunicationIDs.add(documentRef.id);
      } else {
        const activeTestIDs = communications
          .filter((communication) => communication.isTestMode === true && activeCommunicationIDs.has(communication.id))
          .map((communication) => communication.id);
        const now = new Date();
        const isActiveNow = displayPeriods.some((period) =>
          period.startsAt && period.endsAt && period.startsAt <= now && now < period.endsAt
        );
        const hasFuturePeriod = displayPeriods.some((period) =>
          period.startsAt && period.endsAt && now < period.startsAt
        );
        if (hasFuturePeriod && !isActiveNow) {
          const currentPrimaryID = Array.from(activeCommunicationIDs).find((id) =>
            id !== documentRef.id
            && (
              id === admobCommunicationID
              || id === unityCommunicationID
              || communications.find((communication) => communication.id === id)?.isTestMode !== true
            )
          );
          activeCommunicationIDs = new Set([currentPrimaryID || admobCommunicationID, ...activeTestIDs]);
        } else {
          activeCommunicationIDs = new Set([documentRef.id, ...activeTestIDs]);
        }
      }
      isEnabled = true;
      blockHeightPX = classicBlockHeightPX;
      if (enabledInput) enabledInput.checked = true;
      await persistConfig();
      hideForm();
      setStatus(wasEditing ? "Communication modifiée." : "");
    } catch (error) {
      setStatus(error.message || "Impossible d'enregistrer la communication.", "error");
    } finally {
      setFormDisabled(false);
    }
  }

  async function deleteCommunication(id) {
    const communication = communications.find((item) => item.id === id);
    if (!communication) return;
    if (!window.confirm("Supprimer cette communication ?")) return;

    try {
      setStatus("Suppression...");
      await firestore.collection("homeCommunications").doc(id).delete();
      if (communication.storagePath) {
        storage.ref().child(communication.storagePath).delete().catch(() => {});
      }
      if (activeCommunicationIDs.has(id)) {
        activeCommunicationIDs = new Set([admobCommunicationID]);
      }
      isEnabled = true;
      if (enabledInput) enabledInput.checked = true;
      await persistConfig();
      if (editingCommunicationID === id) hideForm();
      setStatus("Communication supprimée.");
    } catch (error) {
      setStatus(error.message || "Impossible de supprimer la communication.", "error");
    }
  }

  async function saveConfig() {
    isEnabled = Boolean(enabledInput?.checked);
    if (isEnabled) {
      activeCommunicationIDs = new Set([admobCommunicationID]);
      blockHeightPX = classicBlockHeightPX;
      renderCommunications();
    } else {
      activeCommunicationIDs = new Set();
      blockHeightPX = classicBlockHeightPX;
      renderCommunications();
    }
    setStatus("");

    try {
      await persistConfig();
      setStatus("");
    } catch (error) {
      setStatus(error.message || "Impossible d'enregistrer l'affichage.", "error");
    }
  }

  function persistConfig() {
    return firestore.collection("appConfiguration").doc("homeCommunication").set({
      isEnabled,
      isTestMode: false,
      blockHeightPX,
      admobBannerMaxHeight,
      unityBannerMaxHeight,
      activeCommunicationIDs: Array.from(activeCommunicationIDs),
      communicationPositions,
      updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }

  function normalizeAdmobBannerMaxHeight(value) {
    const height = Math.round(Number(value) || defaultAdmobBannerMaxHeight);
    return Math.min(300, Math.max(50, height));
  }

  function normalizeUnityBannerMaxHeight(value) {
    const height = Math.round(Number(value) || defaultUnityBannerMaxHeight);
    return Math.min(300, Math.max(50, height));
  }

  function readDateTimeLocal(value) {
    if (!value) return null;
    const date = new Date(value);
    return Number.isFinite(date.getTime()) ? date : null;
  }

  function formatDateTimeLocal(value) {
    const date = getDateFromFirestoreValue(value);
    if (!date) return "";
    const pad = (number) => String(number).padStart(2, "0");
    return [
      date.getFullYear(),
      pad(date.getMonth() + 1),
      pad(date.getDate()),
    ].join("-") + `T${pad(date.getHours())}:${pad(date.getMinutes())}`;
  }

  function getDateFromFirestoreValue(value) {
    if (!value) return null;
    if (typeof value.toDate === "function") return value.toDate();
    if (value instanceof Date) return value;
    return null;
  }

  function renderPeriods(periods) {
    if (!periodsList) return;
    periodsList.innerHTML = "";
    const values = periods.length ? periods : [{ startsAt: null, endsAt: null }];
    values.forEach((period) => addPeriodRow(period, false));
  }

  function addPeriodRow(period = {}, focus = true) {
    if (!periodsList) return;
    const row = document.createElement("div");
    row.className = "field-row communication-period-row";
    row.innerHTML = `
      <div class="field-group"><label>Début</label><input type="datetime-local" data-period-start value="${escapeAttribute(formatDateTimeLocal(period.startsAt))}"></div>
      <div class="field-group"><label>Fin</label><input type="datetime-local" data-period-end value="${escapeAttribute(formatDateTimeLocal(period.endsAt))}"></div>
      <button class="icon-action-button danger-button" type="button" aria-label="Supprimer cette période">×</button>
    `;
    row.querySelector("button")?.addEventListener("click", () => {
      if (periodsList.children.length === 1) {
        row.querySelectorAll("input").forEach((input) => { input.value = ""; });
      } else {
        row.remove();
      }
    });
    periodsList.append(row);
    if (focus) row.querySelector("input")?.focus();
  }

  function readDisplayPeriods() {
    return Array.from(periodsList?.querySelectorAll(".communication-period-row") || [])
      .map((row) => ({
        startsAt: readDateTimeLocal(row.querySelector("[data-period-start]")?.value || ""),
        endsAt: readDateTimeLocal(row.querySelector("[data-period-end]")?.value || ""),
      }))
      .filter((period) => period.startsAt || period.endsAt);
  }

  function communicationPeriods(communication) {
    const periods = Array.isArray(communication.displayPeriods) ? communication.displayPeriods : [];
    if (periods.length) {
      return periods.map((period) => ({
        startsAt: getDateFromFirestoreValue(period.startsAt),
        endsAt: getDateFromFirestoreValue(period.endsAt),
      }));
    }
    const startsAt = getDateFromFirestoreValue(communication.startsAt);
    const endsAt = getDateFromFirestoreValue(communication.endsAt);
    return startsAt || endsAt ? [{ startsAt, endsAt }] : [];
  }

  function periodsOverlap(first, second) {
    return first.startsAt && first.endsAt && second.startsAt && second.endsAt
      && first.startsAt < second.endsAt && second.startsAt < first.endsAt;
  }

  function hasExclusiveScheduleConflict(type, candidatePeriods, ignoredID) {
    return communications.some((communication) => {
      if (communication.id === ignoredID) return false;
      const otherType = getCommunicationType(communication).value;
      if (type !== "sponsored" && otherType !== "sponsored") return false;
      return candidatePeriods.some((candidate) =>
        communicationPeriods(communication).some((period) => periodsOverlap(candidate, period))
      );
    });
  }

  function normalizeBlockHeight(value) {
    const height = Number.parseInt(value, 10);
    if (!Number.isFinite(height)) return classicBlockHeightPX;
    return Math.min(1100, Math.max(120, height));
  }

  function setFormDisabled(isDisabled) {
    form?.querySelectorAll("button, input, select, textarea").forEach((node) => {
      node.disabled = isDisabled;
    });
  }

  function setCommunicationType(type, options = {}) {
    const nextType = ["text", "image", "poll", "sponsored"].includes(type) ? type : "text";
    if (typeInput) typeInput.value = nextType;
    typeChoiceInputs.forEach((input) => {
      input.checked = input.value === nextType;
    });
    updateFormForType();

    if (options.focus === false) return;
    if (nextType === "poll") {
      pollQuestionInput?.focus();
    } else if (nextType === "image") {
      imageDropZone?.focus();
    } else {
      textInput?.focus();
    }
  }

  function updateFormForType() {
    const type = typeInput?.value || "text";
    const isPoll = type === "poll";
    const isImage = type === "image";
    const isSponsored = type === "sponsored";
    const isText = type === "text";
    const isTestSponsored = isSponsored && testModeInput?.checked === true;

    titleInput?.closest(".field-group")?.classList.toggle("is-hidden", isSponsored);
    if (titleInput) titleInput.disabled = isSponsored;

    textGroup?.classList.toggle("is-hidden", !isText);
    imageGroup?.classList.toggle("is-hidden", !isImage && !isSponsored);
    imageOverlayTextGroup?.classList.toggle("is-hidden", !isImage);
    sponsoredGroup?.classList.toggle("is-hidden", !isSponsored);
    pollBuilder?.classList.toggle("is-hidden", !isPoll);
    periodsBuilder?.classList.toggle("is-hidden", isTestSponsored);
    periodsBuilder?.querySelectorAll("input, button").forEach((node) => {
      node.disabled = isTestSponsored;
    });
    if (textInput) {
      textInput.disabled = isPoll;
      textInput.placeholder = "Message visible dans le bloc d'accueil";
    }
    if (pollQuestionInput) pollQuestionInput.disabled = !isPoll;
    pollOptionsList?.querySelectorAll("input").forEach((input) => {
      input.disabled = !isPoll;
    });
    if (imageInput) {
      imageInput.disabled = !isImage && !isSponsored;
    }
    if (imageOverlayTextInput) {
      imageOverlayTextInput.disabled = !isImage;
    }
    imageDropZone?.classList.toggle("is-disabled", !isImage && !isSponsored);
    updateImageStatus();
  }

  function renderPollOptions(options, settings = {}) {
    if (!pollOptionsList) return;
    const values = [...options];
    while (values.length < 2) values.push("");
    pollOptionsList.innerHTML = "";
    values.forEach((value) => addPollOptionInput(value, { focus: false }));
    if (settings.focus !== false) {
      pollOptionsList.querySelector("input")?.focus();
    }
  }

  function addPollOptionInput(value = "", settings = {}) {
    if (!pollOptionsList) return;
    const row = document.createElement("div");
    row.className = "poll-option-row";

    const input = document.createElement("input");
    input.type = "text";
    input.value = value;
    input.placeholder = `Choix ${pollOptionsList.children.length + 1}`;

    const removeButton = document.createElement("button");
    removeButton.className = "icon-action-button danger-button";
    removeButton.type = "button";
    removeButton.setAttribute("aria-label", "Supprimer ce choix");
    removeButton.innerHTML = '<span aria-hidden="true">×</span>';
    removeButton.addEventListener("click", () => {
      if (pollOptionsList.children.length <= 2) {
        input.value = "";
        input.focus();
        return;
      }
      row.remove();
      refreshPollOptionPlaceholders();
    });

    row.append(input, removeButton);
    pollOptionsList.append(row);
    refreshPollOptionPlaceholders();
    updateFormForType();
    if (settings.focus !== false) input.focus();
  }

  function refreshPollOptionPlaceholders() {
    pollOptionsList?.querySelectorAll("input").forEach((input, index) => {
      input.placeholder = `Choix ${index + 1}`;
    });
  }

  function readPollOptions() {
    return Array.from(pollOptionsList?.querySelectorAll("input") || [])
      .map((input) => input.value.trim())
      .filter(Boolean);
  }

  function updateImageStatus() {
    if (!imageStatus) return;
    const file = imageInput?.files?.[0];
    if (typeInput?.value === "image" || typeInput?.value === "sponsored") {
      const existingCommunication = editingCommunicationID
        ? communications.find((item) => item.id === editingCommunicationID)
        : null;
      if (file) {
        imageStatus.textContent = file.name;
      } else if (existingCommunication?.imageURL) {
        imageStatus.textContent = typeInput?.value === "sponsored"
          ? "Média actuel conservé. Nouveau média optionnel."
          : "Média actuel conservé. Nouvelle image/GIF : 1077 x 500 px ; vidéo : format libre.";
      } else {
        imageStatus.textContent = typeInput?.value === "sponsored"
          ? "Image, GIF ou vidéo obligatoire."
          : "Image/GIF : 1077 x 500 px ; vidéo : format libre.";
      }
      return;
    }
    imageStatus.textContent = file ? file.name : "Image disponible uniquement pour le type Image.";
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
    if (!file || !imageInput || imageInput.disabled) return;

    const dataTransfer = new DataTransfer();
    dataTransfer.items.add(file);
    imageInput.files = dataTransfer.files;
    updateImageStatus();
  }

  function setStatus(message, tone = "") {
    if (!statusNode) return;
    statusNode.textContent = normalizeStatusMessage(message);
    statusNode.dataset.tone = tone;
  }

  async function loadVisiblePollResults(renderedCommunications) {
    const pollCommunications = renderedCommunications.filter((communication) => getCommunicationType(communication).value === "poll");
    await Promise.all(pollCommunications.map(async (communication) => {
      try {
        const snapshot = await firestore
          .collection("homeCommunications")
          .doc(communication.id)
          .collection("votes")
          .get();
        const counts = new Map();
        snapshot.docs.forEach((doc) => {
          const option = String(doc.data().option || "").trim();
          if (!option) return;
          counts.set(option, (counts.get(option) || 0) + 1);
        });
        pollResults.set(communication.id, {
          total: snapshot.size,
          counts,
        });
        updatePollResultsCard(communication);
      } catch (error) {
        setStatus(error.message || "Impossible de charger les résultats du sondage.", "error");
      }
    }));
  }

  async function generateSponsoredReport(id) {
    const communication = communications.find((item) => item.id === id);
    if (!communication) return;
    const reportWindow = window.open("", "_blank");
    if (!reportWindow) {
      setStatus("Autorise les fenêtres surgissantes pour créer le rapport PDF.", "error");
      return;
    }
    reportWindow.document.write("<p style='font-family:sans-serif;padding:32px'>Préparation du rapport…</p>");

    try {
      const snapshot = await firestore.collection("homeCommunications").doc(id).collection("adEvents").get();
      const events = snapshot.docs.map((doc) => doc.data());
      const totals = summarizeReportEvents(events);
      const hourly = groupReportEvents(events, (event) => reportHourKey(event.occurredAt));
      const regions = groupReportEvents(events, (event) => String(event.region || event.regionName || "Région non disponible"));
      const periods = communicationPeriods(communication);
      const campaignDate = periods.length
        ? periods.map((period, index) => `Période ${index + 1} : du ${formatReportDate(period.startsAt)} au ${formatReportDate(period.endsAt)} (${formatDurationHours(period.startsAt, period.endsAt)})`).join("\n")
        : formatReportDate(getDateFromFirestoreValue(communication.createdAt));
      const position = Number(communication.position || communicationPositions[id] || 2);
      const reportHTML = buildSponsoredReportHTML({ communication, totals, hourly, regions, campaignDate, periodCount: periods.length, position });
      reportWindow.document.open();
      reportWindow.document.write(reportHTML);
      reportWindow.document.close();
    } catch (error) {
      reportWindow.close();
      setStatus(error.message || "Impossible de créer le rapport.", "error");
    }
  }

  function summarizeReportEvents(events) {
    const impressions = events.filter((event) => event.event === "impression").length;
    const clicks = events.filter((event) => event.event === "click").length;
    const anonymousImpressions = events.filter((event) => event.event === "impression" && !event.visitorID).length;
    const anonymousClicks = events.filter((event) => event.event === "click" && !event.visitorID).length;
    const consentedImpressions = impressions - anonymousImpressions;
    const consentedClicks = clicks - anonymousClicks;
    const visitors = new Set(events.map((event) => event.visitorID).filter(Boolean)).size;
    return { impressions, clicks, consentedImpressions, consentedClicks, anonymousImpressions, anonymousClicks, visitors, ctr: impressions ? (clicks / impressions) * 100 : 0 };
  }

  function groupReportEvents(events, keyForEvent) {
    const groups = new Map();
    events.forEach((event) => {
      const key = keyForEvent(event) || "Non disponible";
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(event);
    });
    return Array.from(groups, ([label, values]) => ({ label, ...summarizeReportEvents(values) }))
      .sort((a, b) => a.label.localeCompare(b.label, "fr"));
  }

  function reportHourKey(value) {
    const date = getDateFromFirestoreValue(value);
    if (!date) return "Heure non disponible";
    const day = new Intl.DateTimeFormat("fr-FR", {
      year: "numeric", month: "2-digit", day: "2-digit",
    }).format(date);
    const hour = String(date.getHours()).padStart(2, "0");
    return `${day} à ${hour}:00`;
  }

  function formatReportDate(date) {
    return date ? new Intl.DateTimeFormat("fr-FR", { dateStyle: "long", timeStyle: "short" }).format(date) : "Non renseignée";
  }

  function formatDurationHours(startsAt, endsAt) {
    if (!startsAt || !endsAt) return "durée non disponible";
    const hours = Math.max(0, (endsAt.getTime() - startsAt.getTime()) / 3600000);
    return `${new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 2 }).format(hours)} h`;
  }

  function reportTableRows(rows) {
    if (!rows.length) return '<tr><td colspan="5" class="empty-report-row">Aucune donnée disponible</td></tr>';
    return rows.map((row) => `<tr><td>${escapeHTML(row.label)}</td><td>${row.impressions}</td><td>${row.clicks}</td><td>${row.ctr.toFixed(2)} %</td><td>${row.visitors}</td></tr>`).join("");
  }

  function reportHourlyTableRows(rows) {
    if (!rows.length) return '<tr><td colspan="9" class="empty-report-row">Aucune donnée disponible</td></tr>';
    return rows.map((row) => `<tr><td>${escapeHTML(row.label)}</td><td>${row.impressions}</td><td>${row.clicks}</td><td>${row.ctr.toFixed(2)} %</td><td>${row.consentedImpressions}</td><td>${row.consentedClicks}</td><td>${row.visitors}</td><td>${row.anonymousImpressions}</td><td>${row.anonymousClicks}</td></tr>`).join("");
  }

  function buildSponsoredReportHTML({ communication, totals, hourly, regions, campaignDate, periodCount, position }) {
    const logoURL = `${window.location.origin}/assets/img/flechemoica-logo.png`;
    const metadata = [
      ["Client", communication.clientName || "Non renseigné"],
      ["N° facture", communication.invoiceNumber || "Non renseigné"],
      [periodCount > 1 ? "Périodes de diffusion" : "Période de diffusion", campaignDate],
      ["Lien de destination", communication.destinationURL || "Non renseigné"],
      ["Emplacement", `Position ${position}`],
    ];
    const tableHead = "<thead><tr><th></th><th>Affichages</th><th>Clics</th><th>CTR</th><th>Visiteurs consentants</th></tr></thead>";
    const hourlyTableHead = "<thead><tr><th>Heure</th><th>Aff. totaux</th><th>Clics totaux</th><th>CTR</th><th>Aff. consentants</th><th>Clics consentants</th><th>Visiteurs consentants</th><th>Aff. anonymes</th><th>Clics anonymes</th></tr></thead>";
    const regionalTableHead = "<thead><tr><th>Région</th><th>Aff. totaux</th><th>Clics totaux</th><th>CTR</th><th>Aff. consentants</th><th>Clics consentants</th><th>Visiteurs consentants</th><th>Aff. anonymes</th><th>Clics anonymes</th></tr></thead>";
    return `<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>Rapport - ${escapeHTML(communication.clientName || "Publicité")}</title><style>
      @page{size:A4;margin:0}*{box-sizing:border-box}body{margin:0;background:#e9eef5;color:#172033;font-family:Inter,ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}.page{position:relative;width:210mm;min-height:297mm;margin:0 auto;padding:20mm 18mm 18mm;background:#fff;page-break-after:always}.page:last-child{page-break-after:auto}.brand{display:flex;align-items:center;gap:14px;padding-bottom:14px;border-bottom:3px solid #c0adee}.brand img{width:54px;height:54px;object-fit:contain}.brand h1{margin:0;color:#18212f;font-family:system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;font-size:22.72px;font-style:italic;font-weight:900;line-height:1.1;letter-spacing:0;text-transform:uppercase}.brand p{margin:4px 0 0;color:#c0aeee;font-size:10px;font-weight:800;letter-spacing:0}.eyebrow{margin-top:28px;color:#8b6fd1;font-size:11px;font-weight:900;letter-spacing:1.6px;text-transform:uppercase}h2{margin:7px 0 20px;font-size:29px}.meta{display:grid;grid-template-columns:58mm 1fr;border:1px solid #dce3ed;border-radius:8px;overflow:hidden}.meta dt,.meta dd{margin:0;padding:10px 12px;border-bottom:1px solid #e7ebf1}.meta dt{background:#f3f0fc;font-weight:800}.meta dd{overflow-wrap:anywhere}.meta dt:last-of-type,.meta dd:last-of-type{border-bottom:0}.metrics{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-top:24px}.metric{padding:14px 10px;border:1px solid #dce3ed;border-radius:8px;text-align:center}.metric strong{display:block;font-size:24px}.metric span{display:block;margin-top:5px;color:#667085;font-size:10px;font-weight:800;text-transform:uppercase}.note{margin-top:18px;padding:12px;border-left:4px solid #c0adee;background:#f8f6ff;color:#596174;font-size:11px;line-height:1.5}table{width:100%;margin-top:18px;border-collapse:collapse;font-size:11px}th{padding:10px 8px;background:#243246;color:#fff;text-align:right}th:first-child{text-align:left}td{padding:10px 8px;border-bottom:1px solid #e2e7ef;text-align:right}td:first-child{text-align:left;font-weight:700}tr:nth-child(even) td{background:#f8fafc}.empty-report-row{text-align:center!important;color:#7c8493;font-weight:400}.footer{position:absolute;right:18mm;bottom:10mm;left:18mm;display:flex;justify-content:space-between;border-top:1px solid #e0e5ec;padding-top:7px;color:#7b8494;font-size:9px}@media print{body{background:#fff}.page{margin:0}}
      .meta dd{white-space:pre-line}.hourly-table{font-size:8px;table-layout:fixed}.hourly-table th,.hourly-table td{padding:8px 3px;overflow-wrap:anywhere}.hourly-table th:first-child,.hourly-table td:first-child{width:24mm}.page-number{position:absolute;right:18mm;bottom:10mm;color:#7b8494;font-size:9px;font-weight:700}@media print{.page,.page:last-child{width:210mm;height:296mm;min-height:0;margin:0;overflow:hidden;page-break-after:auto;break-after:auto}}
    </style></head><body>
      <section class="page"><header class="brand"><img src="${logoURL}" alt=""><div><h1>FLÈCHE-MOI ÇA</h1><p>RAPPORT DE CAMPAGNE PUBLICITAIRE</p></div></header><div class="eyebrow">Publicité client</div><dl class="meta">${metadata.map(([label,value])=>`<dt>${escapeHTML(label)}</dt><dd>${escapeHTML(value)}</dd>`).join("")}</dl><div class="metrics"><div class="metric"><strong>${totals.impressions}</strong><span>Affichages totaux</span></div><div class="metric"><strong>${totals.clicks}</strong><span>Clics totaux</span></div><div class="metric"><strong>${totals.ctr.toFixed(2)} %</strong><span>Taux de clic</span></div><div class="metric"><strong>${totals.consentedImpressions}</strong><span>Affichages consentants</span></div><div class="metric"><strong>${totals.consentedClicks}</strong><span>Clics consentants</span></div><div class="metric"><strong>${totals.visitors}</strong><span>Visiteurs consentants</span></div><div class="metric"><strong>${totals.anonymousImpressions}</strong><span>Affichages anonymes</span></div><div class="metric"><strong>${totals.anonymousClicks}</strong><span>Clics anonymes</span></div></div><div class="page-number">1 / 3</div></section>
      <section class="page"><header class="brand"><img src="${logoURL}" alt=""><div><h1>FLÈCHE-MOI ÇA</h1><p>RAPPORT DE CAMPAGNE PUBLICITAIRE</p></div></header><div class="eyebrow">Détail par heure</div><table class="hourly-table">${hourlyTableHead}<tbody>${reportHourlyTableRows(hourly)}</tbody></table><div class="page-number">2 / 3</div></section>
      <section class="page"><header class="brand"><img src="${logoURL}" alt=""><div><h1>FLÈCHE-MOI ÇA</h1><p>RAPPORT DE CAMPAGNE PUBLICITAIRE</p></div></header><div class="eyebrow">Détail par région</div><table class="hourly-table">${regionalTableHead}<tbody>${reportHourlyTableRows(regions)}</tbody></table><p class="note">Les événements ne contenant aucune région apparaissent dans « Région non disponible ». Aucun emplacement précis ni adresse IP n’est inclus dans ce rapport.</p><div class="page-number">3 / 3</div></section>
      <script>window.addEventListener('load',()=>setTimeout(()=>window.print(),300));<\/script></body></html>`;
  }

  function updatePollResultsCard(communication) {
    const node = listNode?.querySelector(`[data-poll-preview="${escapeAttribute(communication.id)}"]`);
    if (!node) return;
    node.outerHTML = renderCommunicationPreview(communication, { value: "poll" });
  }

  async function deleteExistingPollVotes(communicationID) {
    if (!communicationID) return;
    const snapshot = await firestore
      .collection("homeCommunications")
      .doc(communicationID)
      .collection("votes")
      .get();
    if (snapshot.empty) return;

    const batch = firestore.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }

  function normalizeStatusMessage(message) {
    const value = String(message || "");
    if (/missing or insufficient permissions/i.test(value)) {
      return "Permissions Firebase insuffisantes. Deploie les regles Firestore/Storage puis recharge.";
    }

    return value;
  }

  function getCommunicationType(communication) {
    const storedType = communication.type || "";
    const value = storedType || (communication.imageURL ? "image" : "text");
    const labels = {
      text: "Texte",
      image: "Image",
      poll: "Sondage",
      ad: "Pub",
      unityAd: "Pub Unity",
      sponsored: "Publicité client",
    };

    return { value, label: labels[value] || "Texte" };
  }

  function getCommunicationTitle(communication, type = getCommunicationType(communication)) {
    if (type.value === "sponsored") {
      const clientName = String(communication.clientName || "").trim();
      return clientName ? `Annonce ${clientName}` : "Annonce client";
    }
    const storedTitle = String(communication.title || "").trim();
    if (storedTitle) return storedTitle;
    if (communication.id === unityCommunicationID || type.value === "unityAd") return "Publicité Unity Ads";
    if (communication.id === admobCommunicationID || type.value === "ad") return "Publicité AdMob";
    if (type.value === "poll") return String(communication.text || "").trim() || "Sondage";
    if (type.value === "image") return "Image 1077 x 500";

    const text = String(communication.text || "").trim();
    return text ? text.slice(0, 48) : "Communication";
  }

  function renderCommunicationPreview(communication, type) {
    const text = escapeHTML(communication.text || "");
    const media = renderMediaPreview(communication);

    if (type.value === "sponsored") {
      return `
        <div class="communication-preview communication-preview-image">
          ${media}
          ${renderScheduleOverlay(communication)}
        </div>
      `;
    }

    if (communication.imageURL) {
      const overlayText = escapeHTML(communication.imageOverlayText || "");
      return `
        <div class="communication-preview communication-preview-image">
          ${media}
          ${overlayText ? `<strong class="communication-image-overlay-text">${overlayText}</strong>` : ""}
        </div>
      `;
    }

    if (type.value === "poll") {
      const options = Array.isArray(communication.pollOptions) ? communication.pollOptions.slice(0, 3) : [];
      const counts = pollResults.get(communication.id)?.counts || new Map();
      return `
        <div class="communication-preview communication-preview-poll" data-poll-preview="${escapeAttribute(communication.id)}">
          <strong>${text || "Sondage"}</strong>
          ${options.map((option) => `
            <div class="poll-choice-preview">
              <span>${escapeHTML(option)}</span>
              <b>${counts.get(option) || 0}</b>
            </div>
          `).join("")}
        </div>
      `;
    }

    if (type.value === "ad") {
      return `
        <div class="communication-preview communication-preview-ad">
          <img class="communication-advertiser-logo" src="assets/img/services/admob.svg" alt="AdMob">
          <span>Publicité native</span>
        </div>
      `;
    }
    if (type.value === "unityAd") {
      return `
        <div class="communication-preview communication-preview-ad">
          <img class="communication-advertiser-logo" src="assets/img/services/unity.svg" alt="Unity Ads">
          <span>Bannière LevelPlay</span>
        </div>
      `;
    }
    return `
      <div class="communication-preview communication-preview-text">
        <strong>${text || "Texte"}</strong>
      </div>
    `;
  }

  function renderMediaPreview(communication) {
    if (!communication.imageURL) return "";
    const url = escapeAttribute(communication.imageURL);
    const kind = communication.mediaKind || getMediaKind(communication.mediaType || "");
    if (kind === "video") {
      return `<video class="communication-thumb" src="${url}" autoplay muted loop playsinline preload="metadata"></video>`;
    }
    return `<img class="communication-thumb" src="${url}" alt="">`;
  }

  function renderScheduleSummary(communication) {
    const periods = communicationPeriods(communication);
    if (periods.length > 1) {
      return `<span class="communication-schedule-summary">${periods.length} périodes planifiées</span>`;
    }
    if (periods.length === 1) {
      const [{ startsAt, endsAt }] = periods;
      return `<span class="communication-schedule-summary">Du ${escapeHTML(formatShortDateTime(startsAt))} au ${escapeHTML(formatShortDateTime(endsAt))}</span>`;
    }
    const startsAt = getDateFromFirestoreValue(communication.startsAt);
    const endsAt = getDateFromFirestoreValue(communication.endsAt);
    if (!startsAt && !endsAt) return "";

    const parts = [];
    if (startsAt) parts.push(`Du ${formatShortDateTime(startsAt)}`);
    if (endsAt) parts.push(`au ${formatShortDateTime(endsAt)}`);
    return `<span class="communication-schedule-summary">${escapeHTML(parts.join(" "))}</span>`;
  }

  function renderScheduleOverlay(communication) {
    const periods = communicationPeriods(communication)
      .filter((period) => period.startsAt && period.endsAt)
      .sort((first, second) => first.startsAt - second.startsAt);
    if (!periods.length) {
      return '<span class="communication-ad-periods">Diffusion immédiate</span>';
    }
    return `<span class="communication-ad-periods">${periods.map((period, index) => {
      const prefix = periods.length > 1 ? `<b>${index + 1}</b>` : "";
      return `<span>${prefix}${escapeHTML(formatShortDateTime(period.startsAt))} → ${escapeHTML(formatShortDateTime(period.endsAt))}</span>`;
    }).join("")}</span>`;
  }

  function formatShortDateTime(date) {
    return new Intl.DateTimeFormat("fr-FR", {
      day: "2-digit",
      month: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
    }).format(date);
  }

  function readMediaDimensions(file) {
    if (file.type.startsWith("video/")) {
      return new Promise((resolve, reject) => {
        const video = document.createElement("video");
        const objectURL = URL.createObjectURL(file);
        video.onloadedmetadata = () => {
          const dimensions = { width: video.videoWidth, height: video.videoHeight };
          URL.revokeObjectURL(objectURL);
          resolve(dimensions);
        };
        video.onerror = () => {
          URL.revokeObjectURL(objectURL);
          reject(new Error("Impossible de lire les dimensions de la vidéo."));
        };
        video.src = objectURL;
      });
    }
    return new Promise((resolve, reject) => {
      const image = new Image();
      const objectURL = URL.createObjectURL(file);
      image.onload = () => {
        const dimensions = { width: image.naturalWidth, height: image.naturalHeight };
        URL.revokeObjectURL(objectURL);
        resolve(dimensions);
      };
      image.onerror = () => {
        URL.revokeObjectURL(objectURL);
        reject(new Error("Impossible de lire les dimensions de l'image."));
      };
      image.src = objectURL;
    });
  }

  function getMediaKind(contentType) {
    if (String(contentType).startsWith("video/")) return "video";
    if (contentType === "image/gif") return "gif";
    return "image";
  }

  async function uploadSponsoredImage(communicationID, file) {
    if (!functions) throw new Error("Service d’envoi Cloudflare indisponible.");
    const base64 = await fileToBase64(file);
    const callable = functions.httpsCallable("r2UploadSponsoredImage");
    const response = await callable({
      communicationID,
      contentType: file.type || "image/jpeg",
      base64,
    });
    return { ...response.data, storageProvider: "r2" };
  }

  function fileToBase64(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result || "").split(",").pop() || "");
      reader.onerror = () => reject(new Error("Impossible de lire l’image."));
      reader.readAsDataURL(file);
    });
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
