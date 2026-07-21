const SocialNetworksView = (() => {
  let firestore = null;
  let storage = null;
  let functions = null;
  let viewLoaded = false;
  let viewLoadPromise = null;
  let unsubscribeSettings = null;
  let unsubscribePublications = null;
  let unsubscribeInstagramInbox = null;
  let settings = {};
  let localPublications = [];
  let instagramMedia = [];
  let tiktokVideos = [];
  let previewURL = "";
  let loadingInstagram = false;
  let loadingTikTok = false;
  let cropState = null;
  let cropItems = [];

  function init() {}

  async function start() {
    try {
      await ensureView();
      ensureFirebase();
      bindEvents();
      handleInstagramCallback();
      handleTikTokCallback();
      startListeners();
      loadInstagramDashboard();
      loadTikTokDashboard();
    } catch (error) {
      setStatus(error.message || "Impossible de charger les réseaux sociaux.", "error");
    }
  }

  function stop() {
    if (unsubscribeSettings) unsubscribeSettings();
    if (unsubscribePublications) unsubscribePublications();
    unsubscribeSettings = null;
    unsubscribePublications = null;
    if (unsubscribeInstagramInbox) unsubscribeInstagramInbox();
    unsubscribeInstagramInbox = null;
  }

  async function ensureView() {
    if (viewLoaded) return;
    if (!viewLoadPromise) {
      viewLoadPromise = (async () => {
        const panel = document.getElementById("social-networks-panel");
        if (!panel) throw new Error("Panneau réseaux sociaux introuvable.");
        const response = await fetch(panel.dataset.viewSrc, { cache: "no-store" });
        if (!response.ok) throw new Error("Vue réseaux sociaux introuvable.");
        panel.innerHTML = await response.text();
      })();
    }
    await viewLoadPromise;
    viewLoaded = true;
  }

  function ensureFirebase() {
    AuthGate.ensureFirebase();
    firestore = firestore || firebase.firestore();
    storage = storage || firebase.storage();
    functions = functions || firebase.app().functions("europe-west1");
  }

  function bindEvents() {
    const settingsButton = node("social-settings-button");
    bind(settingsButton, "click", () => {
      const hidden = node("social-settings-panel").classList.toggle("is-hidden");
      settingsButton.setAttribute("aria-expanded", String(!hidden));
    });
    bind(node("instagram-connect-button"), "click", connectInstagram);
    bind(node("tiktok-connect-button"), "click", connectTikTok);
    bind(node("instagram-refresh-messages"), "click", loadInstagramMessages);
    const instagramMessageLink = document.querySelector(".social-profile-instagram .social-message-shortcut");
    bind(instagramMessageLink, "click", () => firestore.collection("instagramInbox").doc("summary").set({ unreadCount: 0 }, { merge: true }).catch(() => {}));
    bind(node("social-add-button"), "click", showComposer);
    bind(node("social-composer-close"), "click", hideComposer);
    bind(node("social-composer-cancel"), "click", hideComposer);
    bind(node("social-composer"), "submit", savePublication);
    document.querySelectorAll("[name='destination']").forEach((input) => bind(input, "change", updateDestinationOptions));

    const input = node("social-media-input");
    const drop = node("social-media-drop");
    bind(input, "change", updateMediaPreview);
    bind(drop, "click", (event) => { if (event.target !== input) input.click(); });
    bind(drop, "keydown", (event) => {
      if (event.key === "Enter" || event.key === " ") { event.preventDefault(); input.click(); }
    });
    bind(drop, "dragover", (event) => { event.preventDefault(); drop.classList.add("is-dragging"); });
    bind(drop, "dragleave", () => drop.classList.remove("is-dragging"));
    bind(drop, "drop", (event) => {
      event.preventDefault();
      drop.classList.remove("is-dragging");
      const files = Array.from(event.dataTransfer.files || []).slice(0, 10);
      if (!files.length) return;
      const transfer = new DataTransfer();
      files.forEach((file) => transfer.items.add(file));
      input.files = transfer.files;
      updateMediaPreview();
    });
    document.querySelectorAll("[data-crop-ratio]").forEach((button) => bind(button, "click", () => setCropRatio(Number(button.dataset.cropRatio))));
    bind(node("social-crop-zoom"), "input", (event) => {
      if (!cropState) return;
      cropState.zoom = Number(event.target.value);
      clampCropOffset();
      renderCrop();
    });
    bind(node("social-media-preview"), "pointerdown", startCropDrag);
  }

  function bind(element, eventName, handler) {
    if (!element || element.dataset[`bound${eventName}`]) return;
    element.addEventListener(eventName, handler);
    element.dataset[`bound${eventName}`] = "true";
  }

  function startListeners() {
    if (!unsubscribeSettings) {
      unsubscribeSettings = firestore.collection("socialNetworkSettings").doc("accounts").onSnapshot(
        (snapshot) => { settings = snapshot.exists ? snapshot.data() : {}; renderProfiles(); },
        (error) => setStatus(error.message || "Impossible de charger les profils.", "error")
      );
    }
    if (!unsubscribePublications) {
      unsubscribePublications = firestore.collection("socialPublications").orderBy("createdAt", "desc").limit(60).onSnapshot(
        (snapshot) => {
          localPublications = snapshot.docs.map((document) => ({ id: document.id, ...document.data() }));
          renderTikTokPublications();
        },
        (error) => setStatus(error.message || "Impossible de charger les publications.", "error")
      );
    }
    if (!unsubscribeInstagramInbox) {
      unsubscribeInstagramInbox = firestore.collection("instagramInbox").doc("summary").onSnapshot((snapshot) => {
        updateInstagramMessageBadge(Number(snapshot.data()?.unreadCount || 0));
      });
    }
  }

  async function connectInstagram() {
    const button = node("instagram-connect-button");
    button.disabled = true;
    setStatus("Préparation de la connexion Instagram…");
    try {
      const result = await functions.httpsCallable("instagramCreateAuthLink")({});
      if (!result.data?.url) throw new Error("Lien de connexion Instagram manquant.");
      window.location.href = result.data.url;
    } catch (error) {
      button.disabled = false;
      setStatus(callableMessage(error, "Connexion Instagram impossible."), "error");
    }
  }

  async function connectTikTok() {
    const button = node("tiktok-connect-button");
    button.disabled = true;
    setStatus("Préparation de la connexion TikTok…");
    try {
      const result = await functions.httpsCallable("tiktokCreateAuthLink")({});
      if (!result.data?.url) throw new Error("Lien de connexion TikTok manquant.");
      window.location.href = result.data.url;
    } catch (error) {
      button.disabled = false;
      setStatus(callableMessage(error, "Connexion TikTok impossible."), "error");
    }
  }

  function handleInstagramCallback() {
    const url = new URL(window.location.href);
    const state = url.searchParams.get("instagram");
    if (!state) return;
    setStatus(state === "connected" ? "Instagram est connecté." : (url.searchParams.get("message") || "Connexion Instagram impossible."), state === "connected" ? "success" : "error");
    window.history.replaceState({}, "", "/reseaux-sociaux.html");
  }

  function handleTikTokCallback() {
    const url = new URL(window.location.href);
    const state = url.searchParams.get("tiktok");
    if (!state) return;
    setStatus(state === "connected" ? "TikTok est connecté." : (url.searchParams.get("message") || "Connexion TikTok impossible."), state === "connected" ? "success" : "error");
    window.history.replaceState({}, "", "/reseaux-sociaux.html");
  }

  async function loadInstagramDashboard() {
    if (loadingInstagram) return;
    loadingInstagram = true;
    try {
      const result = await functions.httpsCallable("instagramGetDashboard")({});
      instagramMedia = result.data?.media || [];
      renderInstagramProfile(result.data?.profile || {});
      renderInstagramPublications();
      loadInstagramMessages();
    } catch (error) {
      const message = callableMessage(error, "Instagram n’est pas encore connecté.");
      if (!message.toLowerCase().includes("connecte d’abord")) setStatus(message, "error");
      renderInstagramPublications();
    } finally {
      loadingInstagram = false;
    }
  }

  async function loadTikTokDashboard() {
    if (loadingTikTok) return;
    loadingTikTok = true;
    try {
      const result = await functions.httpsCallable("tiktokGetDashboard")({});
      tiktokVideos = result.data?.videos || [];
      renderTikTokProfile(result.data?.profile || {});
      renderTikTokPrivacyOptions(result.data?.creator?.privacy_level_options || []);
      renderTikTokPublications();
    } catch (error) {
      const message = callableMessage(error, "TikTok n’est pas encore connecté.");
      if (!message.toLowerCase().includes("connecte d’abord")) setStatus(message, "error");
      renderTikTokPublications();
    } finally {
      loadingTikTok = false;
    }
  }

  async function loadInstagramMessages() {
    const list = node("instagram-message-list");
    if (list) list.innerHTML = '<div class="social-empty-state"><strong>Chargement des messages…</strong></div>';
    try {
      const result = await functions.httpsCallable("instagramGetConversations")({});
      if (!result.data?.available) throw new Error(result.data?.message || "La messagerie n’est pas encore autorisée par Meta.");
      const conversations = result.data.conversations || [];
      updateInstagramMessageBadge(conversations.length);
      if (list) renderInstagramMessages(conversations);
    } catch (error) {
      updateInstagramMessageBadge(0);
      if (list) list.innerHTML = `<div class="social-empty-state"><strong>Messages indisponibles</strong><p>${escapeHTML(callableMessage(error, "Connecte Instagram et autorise les messages."))}</p></div>`;
    }
  }

  function updateInstagramMessageBadge(count) {
    const badge = document.querySelector("[data-message-badge='instagram']");
    if (!badge) return;
    badge.textContent = String(Math.min(Number(count) || 0, 99));
    badge.classList.toggle("is-hidden", !count);
  }

  function renderInstagramMessages(conversations) {
    const list = node("instagram-message-list");
    if (!list) return;
    if (!conversations.length) {
      list.innerHTML = '<div class="social-empty-state"><strong>Aucun message ni demande</strong><p>Les conversations et demandes récentes autorisées par Instagram apparaîtront ici.</p></div>';
      return;
    }
    list.innerHTML = conversations.map((conversation) => {
      const participants = (conversation.participants?.data || []).filter((participant) => participant.username !== settings.instagram?.handle);
      const participant = participants[0] || conversation.participants?.data?.[0] || {};
      const message = conversation.messages?.data?.[0] || {};
      return `<article class="social-message-row">
        <div class="social-message-avatar">${escapeHTML((participant.username || "?").slice(0, 1).toUpperCase())}</div>
        <div><strong>@${escapeHTML(participant.username || "instagram")}</strong><p>${escapeHTML(message.message || "Pièce jointe ou nouveau message")}</p></div>
        <time>${formatDate(message.created_time || conversation.updated_time)}</time>
      </article>`;
    }).join("");
  }

  function renderProfiles() {
    const instagram = settings.instagram || {};
    renderInstagramProfile(instagram.profile || { username: instagram.handle });
    const connected = instagram.connected === true;
    const connectButton = node("instagram-connect-button");
    if (connectButton) connectButton.textContent = connected ? "Reconnecter Instagram" : "Connecter Instagram";
    const instagramLabel = document.querySelector("[data-social-connection-label='instagram']");
    if (instagramLabel) instagramLabel.textContent = connected ? `@${instagram.handle || "flechemoica"} · connecté` : "Non connecté";
    const instagramBadge = document.querySelector("[data-social-badge='instagram']");
    if (instagramBadge) {
      instagramBadge.textContent = "À configurer";
      instagramBadge.classList.toggle("is-hidden", connected);
    }

    const tiktok = settings.tiktok || {};
    renderTikTokProfile(tiktok.profile || { username: tiktok.handle });
    const tiktokConnected = tiktok.connected === true;
    const tiktokButton = node("tiktok-connect-button");
    if (tiktokButton) tiktokButton.textContent = tiktokConnected ? "Reconnecter TikTok" : "Connecter TikTok";
    const badge = document.querySelector("[data-social-badge='tiktok']");
    if (badge) {
      badge.textContent = "À configurer";
      badge.classList.toggle("is-hidden", tiktokConnected);
    }
    const label = document.querySelector("[data-social-connection-label='tiktok']");
    if (label) label.textContent = tiktokConnected ? `@${normalizeHandle(tiktok.handle || "flechemoica")} · connecté` : "Non connecté";
    renderTikTokPrivacyOptions(tiktok.creator?.privacy_level_options || []);
  }

  function renderInstagramProfile(profile) {
    const handle = normalizeHandle(profile.username || settings.instagram?.handle || "flechemoica");
    const picture = document.querySelector("[data-instagram-profile-picture]");
    if (picture && profile.profile_picture_url) picture.src = profile.profile_picture_url;
    const name = document.querySelector("[data-social-name='instagram']");
    if (name) name.textContent = profile.name || handle || "Flèche-moi ça";
    document.querySelectorAll("[data-social-handle='instagram']").forEach((item) => { item.textContent = handle; });
    const link = document.querySelector("[data-social-link='instagram']");
    if (link) link.href = `https://www.instagram.com/${encodeURIComponent(handle)}/`;
    setText("[data-instagram-biography]", profile.biography || "");
    setText("[data-instagram-post-count]", numberLabel(profile.media_count));
    setText("[data-instagram-followers]", numberLabel(profile.followers_count));
    setText("[data-instagram-following]", numberLabel(profile.follows_count));
  }

  function renderTikTokProfile(profile) {
    const handle = normalizeHandle(profile.username || settings.tiktok?.handle || "flechemoica");
    const picture = document.querySelector("[data-tiktok-profile-picture]");
    if (picture && profile.avatar_url) picture.src = profile.avatar_url;
    const name = document.querySelector("[data-social-name='tiktok']");
    if (name) name.textContent = profile.display_name || handle || "Flèche-moi ça";
    document.querySelectorAll("[data-social-handle='tiktok']").forEach((item) => { item.textContent = handle; });
    const link = document.querySelector("[data-social-link='tiktok']");
    if (link) link.href = profile.profile_deep_link || `https://www.tiktok.com/@${encodeURIComponent(handle)}`;
  }

  function renderTikTokPrivacyOptions(options) {
    const select = node("tiktok-privacy-level");
    if (!select) return;
    const labels = { PUBLIC_TO_EVERYONE: "Tout le monde", MUTUAL_FOLLOW_FRIENDS: "Amis", FOLLOWER_OF_CREATOR: "Abonnés", SELF_ONLY: "Moi uniquement" };
    const previous = select.value;
    select.innerHTML = options.length
      ? options.map((value) => `<option value="${escapeAttribute(value)}">${escapeHTML(labels[value] || value)}</option>`).join("")
      : '<option value="">Connecte TikTok pour charger les choix</option>';
    select.disabled = !options.length;
    if (options.includes(previous)) select.value = previous;
  }

  function updateDestinationOptions() {
    const isTikTok = document.querySelector("[name='destination']:checked")?.value === "tiktok";
    node("tiktok-publish-options")?.classList.toggle("is-hidden", !isTikTok);
    const select = node("tiktok-privacy-level");
    if (select) select.required = isTikTok;
  }

  function showComposer() {
    node("social-composer").classList.remove("is-hidden");
    node("social-composer").scrollIntoView({ behavior: "smooth", block: "start" });
    updateDestinationOptions();
  }

  function hideComposer() {
    node("social-composer").reset();
    node("social-composer").classList.add("is-hidden");
    clearMediaPreview();
  }

  function updateMediaPreview() {
    const files = Array.from(node("social-media-input").files || []);
    if (!files.length) return;
    if (cropItems.length && files.every((file) => file.type.startsWith("image/"))) {
      if (cropItems.length + files.length > 10) {
        syncCropInputFiles();
        return setStatus("Instagram accepte au maximum 10 images par carrousel.", "error");
      }
      const ratio = cropItems[0].ratio;
      const firstNewIndex = cropItems.length;
      files.forEach((file) => {
        const image = new Image();
        const url = URL.createObjectURL(file);
        image.alt = `Aperçu ${cropItems.length + 1}`;
        const item = { file, image, url, ratio, zoom: 1, offsetX: 0, offsetY: 0 };
        image.onload = () => { if (cropState === item) renderCrop(); };
        image.src = url;
        cropItems.push(item);
      });
      syncCropInputFiles();
      renderCropItem(firstNewIndex);
      setStatus(`${cropItems.length} images dans le carrousel.`, "success");
      return;
    }
    clearMediaPreview();
    if (files.length > 10) {
      node("social-media-input").value = "";
      return setStatus("Instagram accepte au maximum 10 images par carrousel.", "error");
    }
    if (files.length > 1 && files.some((file) => !file.type.startsWith("image/"))) {
      node("social-media-input").value = "";
      return setStatus("Le carrousel accepte uniquement plusieurs images pour le moment.", "error");
    }
    previewURL = URL.createObjectURL(files[0]);
    const preview = node("social-media-preview");
    if (files[0].type.startsWith("video/")) {
      cropState = null;
      preview.classList.remove("is-croppable");
      preview.innerHTML = `<video src="${previewURL}" muted playsinline controls></video>`;
      node("social-crop-controls").classList.add("is-hidden");
    } else {
      cropItems = files.map((file, index) => {
        const image = new Image();
        const url = index === 0 ? previewURL : URL.createObjectURL(file);
        image.alt = `Aperçu ${index + 1}`;
        const item = { file, image, url, ratio: 1, zoom: 1, offsetX: 0, offsetY: 0 };
        image.onload = () => { if (cropState === item) renderCrop(); };
        image.src = url;
        return item;
      });
      cropState = cropItems[0];
      preview.classList.add("is-croppable");
      node("social-crop-controls").classList.remove("is-hidden");
      node("social-crop-zoom").value = "1";
      renderCropItem(0);
      renderCropThumbnails();
      setCropRatio(1);
    }
    preview.classList.remove("is-hidden");
  }

  function clearMediaPreview() {
    if (cropItems.length) cropItems.forEach((item) => URL.revokeObjectURL(item.url));
    else if (previewURL) URL.revokeObjectURL(previewURL);
    previewURL = "";
    cropState = null;
    cropItems = [];
    const preview = node("social-media-preview");
    if (preview) { preview.innerHTML = ""; preview.classList.remove("is-croppable"); preview.classList.add("is-hidden"); }
    const controls = node("social-crop-controls");
    if (controls) controls.classList.add("is-hidden");
    const thumbnails = node("social-media-thumbnails");
    if (thumbnails) { thumbnails.innerHTML = ""; thumbnails.classList.add("is-hidden"); }
  }

  function renderCropThumbnails() {
    const thumbnails = node("social-media-thumbnails");
    if (!thumbnails) return;
    thumbnails.innerHTML = cropItems.map((item, index) => `<div class="social-media-thumbnail-wrap" draggable="true" data-crop-drag-index="${index}">
      <button class="social-media-thumbnail${item === cropState ? " is-active" : ""}" type="button" data-crop-index="${index}" aria-label="Modifier l’image ${index + 1}"><img src="${item.url}" alt=""></button>
      <button class="social-media-thumbnail-remove" type="button" data-crop-remove-index="${index}" aria-label="Supprimer l’image ${index + 1}">−</button>
    </div>`).join("");
    thumbnails.classList.toggle("is-hidden", cropItems.length < 2);
    thumbnails.querySelectorAll("[data-crop-index]").forEach((button) => button.addEventListener("click", () => renderCropItem(Number(button.dataset.cropIndex))));
    thumbnails.querySelectorAll("[data-crop-remove-index]").forEach((button) => button.addEventListener("click", () => removeCropItem(Number(button.dataset.cropRemoveIndex))));
    thumbnails.querySelectorAll("[data-crop-drag-index]").forEach((item) => {
      item.addEventListener("dragstart", (event) => {
        event.dataTransfer.effectAllowed = "move";
        event.dataTransfer.setData("text/plain", item.dataset.cropDragIndex);
        item.classList.add("is-dragging");
      });
      item.addEventListener("dragend", () => item.classList.remove("is-dragging"));
      item.addEventListener("dragover", (event) => { event.preventDefault(); event.dataTransfer.dropEffect = "move"; });
      item.addEventListener("drop", (event) => {
        event.preventDefault();
        const fromIndex = Number(event.dataTransfer.getData("text/plain"));
        const toIndex = Number(item.dataset.cropDragIndex);
        reorderCropItem(fromIndex, toIndex);
      });
    });
  }

  function syncCropInputFiles() {
    const transfer = new DataTransfer();
    cropItems.forEach((item) => transfer.items.add(item.file));
    node("social-media-input").files = transfer.files;
  }

  function reorderCropItem(fromIndex, toIndex) {
    if (!Number.isInteger(fromIndex) || !Number.isInteger(toIndex) || fromIndex === toIndex || !cropItems[fromIndex] || !cropItems[toIndex]) return;
    const [moved] = cropItems.splice(fromIndex, 1);
    cropItems.splice(toIndex, 0, moved);
    syncCropInputFiles();
    renderCropThumbnails();
  }

  function removeCropItem(index) {
    const removed = cropItems[index];
    if (!removed) return;
    cropItems.splice(index, 1);
    URL.revokeObjectURL(removed.url);
    if (!cropItems.length) {
      node("social-media-input").value = "";
      clearMediaPreview();
      return;
    }
    syncCropInputFiles();
    const nextIndex = cropState === removed ? Math.min(index, cropItems.length - 1) : cropItems.indexOf(cropState);
    renderCropItem(Math.max(0, nextIndex));
  }

  function renderCropItem(index) {
    const item = cropItems[index];
    if (!item) return;
    cropState = item;
    const preview = node("social-media-preview");
    preview.innerHTML = "";
    preview.appendChild(item.image);
    preview.style.setProperty("--crop-ratio", String(item.ratio));
    node("social-crop-zoom").value = String(item.zoom);
    renderCropThumbnails();
    requestAnimationFrame(renderCrop);
  }

  function setCropRatio(ratio) {
    if (!cropState) return;
    cropItems.forEach((item) => {
      item.ratio = ratio;
      item.offsetX = 0;
      item.offsetY = 0;
    });
    cropState.ratio = ratio;
    const preview = node("social-media-preview");
    preview.style.setProperty("--crop-ratio", String(ratio));
    document.querySelectorAll("[data-crop-ratio]").forEach((button) => button.classList.toggle("is-active", Number(button.dataset.cropRatio) === ratio));
    requestAnimationFrame(renderCrop);
  }

  function cropMetrics(item = cropState) {
    if (!item) return null;
    const preview = node("social-media-preview");
    const width = preview.clientWidth;
    const height = preview.clientHeight;
    const baseScale = Math.max(width / item.image.naturalWidth, height / item.image.naturalHeight);
    const scale = baseScale * item.zoom;
    return { width, height, scale, imageWidth: item.image.naturalWidth * scale, imageHeight: item.image.naturalHeight * scale };
  }

  function clampCropOffset() {
    const metrics = cropMetrics();
    if (!metrics) return;
    const maxX = Math.max(0, (metrics.imageWidth - metrics.width) / 2);
    const maxY = Math.max(0, (metrics.imageHeight - metrics.height) / 2);
    cropState.offsetX = Math.max(-maxX, Math.min(maxX, cropState.offsetX));
    cropState.offsetY = Math.max(-maxY, Math.min(maxY, cropState.offsetY));
  }

  function renderCrop() {
    const metrics = cropMetrics();
    if (!metrics) return;
    clampCropOffset();
    cropState.image.style.transform = `translate(calc(-50% + ${cropState.offsetX}px), calc(-50% + ${cropState.offsetY}px)) scale(${metrics.scale})`;
  }

  function startCropDrag(event) {
    if (!cropState || event.button !== 0) return;
    const preview = node("social-media-preview");
    const startX = event.clientX;
    const startY = event.clientY;
    const initialX = cropState.offsetX;
    const initialY = cropState.offsetY;
    preview.setPointerCapture(event.pointerId);
    const move = (moveEvent) => {
      cropState.offsetX = initialX + moveEvent.clientX - startX;
      cropState.offsetY = initialY + moveEvent.clientY - startY;
      clampCropOffset();
      renderCrop();
    };
    const end = () => {
      preview.removeEventListener("pointermove", move);
      preview.removeEventListener("pointerup", end);
      preview.removeEventListener("pointercancel", end);
    };
    preview.addEventListener("pointermove", move);
    preview.addEventListener("pointerup", end);
    preview.addEventListener("pointercancel", end);
  }

  async function croppedImageFile(originalFile, item = cropState) {
    if (!item) return originalFile;
    if (!item.image.complete || !item.image.naturalWidth) await item.image.decode();
    const metrics = cropMetrics(item);
    if (!metrics) return originalFile;
    const outputWidth = 1080;
    const outputHeight = Math.round(outputWidth / item.ratio);
    const imageLeft = (metrics.width - metrics.imageWidth) / 2 + item.offsetX;
    const imageTop = (metrics.height - metrics.imageHeight) / 2 + item.offsetY;
    const sourceX = Math.max(0, -imageLeft / metrics.scale);
    const sourceY = Math.max(0, -imageTop / metrics.scale);
    const sourceWidth = metrics.width / metrics.scale;
    const sourceHeight = metrics.height / metrics.scale;
    const canvas = document.createElement("canvas");
    canvas.width = outputWidth;
    canvas.height = outputHeight;
    const context = canvas.getContext("2d");
    context.imageSmoothingEnabled = true;
    context.imageSmoothingQuality = "high";
    context.drawImage(item.image, sourceX, sourceY, sourceWidth, sourceHeight, 0, 0, outputWidth, outputHeight);
    const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 1));
    if (!blob) throw new Error("Impossible de préparer l’image recadrée.");
    return new File([blob], `${originalFile.name.replace(/\.[^.]+$/, "")}-instagram.jpg`, { type: "image/jpeg" });
  }

  async function savePublication(event) {
    event.preventDefault();
    const form = event.currentTarget;
    const originalFiles = cropItems.length ? cropItems.map((item) => item.file) : Array.from(node("social-media-input").files || []);
    const originalFile = originalFiles[0];
    const destinations = Array.from(form.querySelectorAll("[name='destination']:checked")).map((input) => input.value);
    if (!originalFile) return setStatus("Choisis une photo ou une vidéo.", "error");
    if (!destinations.length) return setStatus("Choisis au moins un réseau.", "error");
    if (!originalFile.type.startsWith("image/") && !originalFile.type.startsWith("video/")) return setStatus("Format non pris en charge.", "error");
    if (originalFile.size > 100 * 1024 * 1024) return setStatus("Le média dépasse 100 Mo.", "error");
    const button = form.querySelector("button[type='submit']");
    button.disabled = true;
    setStatus("Téléversement du contenu…");
    try {
      const preparedFiles = originalFiles.length > 1
        ? await Promise.all(originalFiles.map((file, index) => croppedImageFile(file, cropItems[index])))
        : [originalFile.type.startsWith("image/") ? await croppedImageFile(originalFile) : originalFile];
      const reference = firestore.collection("socialPublications").doc();
      const mediaURLs = [];
      for (const [index, file] of preparedFiles.entries()) {
        const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, "-");
        const upload = await storage.ref(`socialPublications/${reference.id}/${Date.now()}-${index}-${safeName}`).put(file, { contentType: file.type });
        mediaURLs.push(await upload.ref.getDownloadURL());
      }
      const mediaURL = mediaURLs[0];
      const mediaType = preparedFiles.length > 1 ? "carousel" : (preparedFiles[0].type.startsWith("video/") ? "video" : "image");
      const caption = node("social-caption").value.trim();
      let instagramID = null;
      let tiktokPublishID = null;
      if (destinations.includes("instagram")) {
        setStatus("Publication sur Instagram…");
        const result = await functions.httpsCallable("instagramPublishMedia")({ mediaURL, mediaURLs, mediaType, caption });
        instagramID = result.data?.id || null;
      }
      if (destinations.includes("tiktok")) {
        const privacyLevel = node("tiktok-privacy-level")?.value || "";
        if (!privacyLevel) throw new Error("Choisis la confidentialité TikTok.");
        setStatus("Publication sur TikTok…");
        const result = await functions.httpsCallable("tiktokPublishMedia")({ mediaURL, mediaURLs, mediaType, caption, privacyLevel });
        tiktokPublishID = result.data?.publishID || null;
      }
      await reference.set({
        caption, destinations, mediaURL, mediaURLs, mediaType, instagramID, tiktokPublishID,
        status: "published",
        createdAt: firebase.firestore.FieldValue.serverTimestamp(),
        createdBy: firebase.auth().currentUser?.uid || null,
      });
      hideComposer();
      setStatus(destinations.includes("instagram") ? "Publication envoyée sur Instagram." : "Publication envoyée sur TikTok.", "success");
      if (destinations.includes("instagram")) setTimeout(loadInstagramDashboard, 2500);
      if (destinations.includes("tiktok")) setTimeout(loadTikTokDashboard, 4000);
    } catch (error) {
      setStatus(callableMessage(error, "Publication impossible."), "error");
    } finally { button.disabled = false; }
  }

  function renderInstagramPublications() {
    const grid = document.querySelector("[data-social-grid='instagram']");
    const count = document.querySelector("[data-social-count='instagram']");
    if (count) count.textContent = `${instagramMedia.length} publication${instagramMedia.length > 1 ? "s" : ""}`;
    grid.innerHTML = instagramMedia.length ? instagramMedia.map((media) => {
      const source = media.thumbnail_url || media.media_url;
      return `<a class="social-grid-item" href="${escapeAttribute(media.permalink)}" target="_blank" rel="noopener noreferrer" title="Ouvrir la publication sur Instagram">
        <img src="${escapeAttribute(source)}" alt="${escapeAttribute(media.caption || "Publication Instagram")}">
        ${media.media_type === "VIDEO" || media.media_type === "REELS" ? '<span class="social-video-mark">▶</span>' : ""}
        <span class="social-grid-engagement"><span aria-label="J’aime">♥ ${numberLabel(media.like_count || 0)}</span><span aria-label="Commentaires">💬 ${numberLabel(media.comments_count || 0)}</span></span>
      </a>`;
    }).join("") : emptyGrid("Aucune publication Instagram");
  }

  function renderTikTokPublications() {
    const grid = document.querySelector("[data-social-grid='tiktok']");
    if (!grid) return;
    const count = document.querySelector("[data-social-count='tiktok']");
    if (count) count.textContent = `${tiktokVideos.length} publication${tiktokVideos.length > 1 ? "s" : ""}`;
    grid.innerHTML = tiktokVideos.length ? tiktokVideos.map((video) => `<a class="social-grid-item" href="${escapeAttribute(video.share_url || video.embed_link)}" target="_blank" rel="noopener noreferrer" title="Ouvrir la publication sur TikTok">
      <img src="${escapeAttribute(video.cover_image_url)}" alt="${escapeAttribute(video.video_description || video.title || "Publication TikTok")}">
      <span class="social-video-mark">▶</span>
      <span class="social-grid-engagement"><span aria-label="J’aime">♥ ${numberLabel(video.like_count || 0)}</span><span aria-label="Commentaires">💬 ${numberLabel(video.comment_count || 0)}</span></span>
    </a>`).join("") : emptyGrid("Aucune publication TikTok");
  }

  function emptyGrid(title) {
    return `<div class="social-empty-state"><span aria-hidden="true">▦</span><strong>${title}</strong><p>Utilise le bouton + pour ajouter un contenu.</p></div>`;
  }

  function callableMessage(error, fallback) { return error?.details || error?.message || fallback; }
  function normalizeHandle(value) { return String(value || "").trim().replace(/^@+/, "").replace(/\s+/g, ""); }
  function numberLabel(value) { return Number.isFinite(Number(value)) ? new Intl.NumberFormat("fr-FR").format(Number(value)) : "—"; }
  function formatDate(value) { const date = new Date(value); return Number.isNaN(date.getTime()) ? "" : new Intl.DateTimeFormat("fr-FR", { day: "2-digit", month: "short" }).format(date); }
  function setText(selector, value) { const element = document.querySelector(selector); if (element) element.textContent = value; }
  function escapeHTML(value) { return String(value || "").replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;"); }
  function escapeAttribute(value) { return escapeHTML(value); }
  function setStatus(message, tone = "") { const status = node("social-status"); if (!status) return; status.textContent = message; if (tone) status.dataset.tone = tone; else status.removeAttribute("data-tone"); }
  function node(id) { return document.getElementById(id); }

  return { init, start, stop };
})();
