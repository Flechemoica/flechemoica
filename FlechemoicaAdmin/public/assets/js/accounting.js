const AccountingView = (() => {
  let functions = null;
  let firestore = null;
  let viewLoaded = false;
  let viewLoadPromise = null;
  let started = false;

  let statusNode = null;
  let connectButton = null;
  let connectCardButton = null;
  let refreshButton = null;
  let settingsButton = null;
  let settingsPanel = null;
  let searchInput = null;
  let periodStartInput = null;
  let periodEndInput = null;
  let connectionTitle = null;
  let connectionDetail = null;
  let totalBalance = null;
  let accountCount = null;
  let transactionCount = null;
  let lastUpdate = null;
  let accountList = null;
  let hiddenCount = null;
  let hiddenOperationList = null;
  let transactionsBody = null;
  let operationModal = null;
  let operationForm = null;
  let operationCloseButton = null;
  let operationHideButton = null;
  let categoryOptions = null;
  let categoryAddButton = null;
  let categoryForm = null;
  let categoryNameInput = null;
  let categoryList = null;
  const customCategories = new Set();
  const deletedCategories = new Set();
  let currentTransactions = [];
  let currentHiddenTransactions = [];
  let refreshPromise = null;
  let reconciliationPromise = null;
  let dateFiltersInitialized = false;

  function init() {
    if (document.body.dataset.accountingRefreshBound) return;

    document.addEventListener("click", (event) => {
      const button = event.target.closest("#accounting-refresh-button");
      if (!button) return;

      event.preventDefault();
      refreshAccountingData();
    });
    document.body.dataset.accountingRefreshBound = "true";
  }

  async function start() {
    started = true;

    try {
      await ensureView();
      ensureFirebase();
      bindEvents();
      handlePowensCallback();
      await loadAccountingData();
    } catch (error) {
      resolveNodes();
      setStatus(error.message || "Impossible de charger la comptabilité.", "error");
    }
  }

  function stop() {
    started = false;
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
    const panel = document.getElementById("accounting-panel");
    if (!panel) throw new Error("Panneau comptabilité introuvable.");

    const viewSrc = panel.dataset.viewSrc;
    if (viewSrc && !panel.innerHTML.trim()) {
      const response = await fetch(viewSrc, { cache: "no-store" });
      if (!response.ok) throw new Error("Vue comptabilité introuvable.");
      panel.innerHTML = await response.text();
    }
  }

  function ensureFirebase() {
    AuthGate.ensureFirebase();
    functions = functions || (firebase.functions ? firebase.app().functions("europe-west1") : null);
    firestore = firestore || (firebase.firestore ? firebase.firestore() : null);

    if (!functions || !firestore) {
      throw new Error("Services Firebase indisponibles.");
    }
  }

  function resolveNodes() {
    statusNode = document.getElementById("accounting-status");
    connectButton = document.getElementById("accounting-connect-button");
    connectCardButton = document.getElementById("accounting-connect-card-button");
    refreshButton = document.getElementById("accounting-refresh-button");
    settingsButton = document.getElementById("accounting-settings-button");
    settingsPanel = document.getElementById("accounting-settings-panel");
    searchInput = document.getElementById("accounting-search-input");
    periodStartInput = document.getElementById("accounting-period-start");
    periodEndInput = document.getElementById("accounting-period-end");

    if (!dateFiltersInitialized && periodStartInput && periodEndInput) {
      const now = new Date();
      periodStartInput.value = formatDateInputLocal(new Date(now.getFullYear(), 0, 1));
      periodEndInput.value = formatDateInputLocal(new Date(now.getFullYear(), now.getMonth() + 1, 0));
      dateFiltersInitialized = true;
    }
    connectionTitle = document.getElementById("accounting-connection-title");
    connectionDetail = document.getElementById("accounting-connection-detail");
    totalBalance = document.getElementById("accounting-total-balance");
    accountCount = document.getElementById("accounting-account-count");
    transactionCount = document.getElementById("accounting-transaction-count");
    lastUpdate = document.getElementById("accounting-last-update");
    accountList = document.getElementById("accounting-account-list");
    hiddenCount = document.getElementById("accounting-hidden-count");
    hiddenOperationList = document.getElementById("accounting-hidden-operation-list");
    transactionsBody = document.getElementById("accounting-transactions-body");
    operationModal = document.getElementById("accounting-operation-modal");
    operationForm = document.getElementById("accounting-operation-form");
    operationCloseButton = document.getElementById("accounting-operation-close");
    operationHideButton = document.getElementById("accounting-operation-hide");
    categoryOptions = document.getElementById("operation-category");
    categoryAddButton = document.getElementById("operation-category-add");
    categoryForm = document.getElementById("accounting-category-form");
    categoryNameInput = document.getElementById("accounting-category-name");
    categoryList = document.getElementById("accounting-category-list");
  }

  function bindEvents() {
    [connectButton, connectCardButton].forEach((button) => {
      if (button && !button.dataset.bound) {
        button.addEventListener("click", connectPowens);
        button.dataset.bound = "true";
      }
    });

    if (settingsButton && !settingsButton.dataset.bound) {
      settingsButton.addEventListener("click", toggleSettingsPanel);
      settingsButton.dataset.bound = "true";
    }

    if (searchInput && !searchInput.dataset.bound) {
      searchInput.addEventListener("input", () => renderTransactions(currentTransactions));
      searchInput.dataset.bound = "true";
    }

    [periodStartInput, periodEndInput].forEach((input) => {
      if (input && !input.dataset.bound) {
        input.addEventListener("change", () => renderTransactions(currentTransactions));
        input.dataset.bound = "true";
      }
    });

    if (operationCloseButton && !operationCloseButton.dataset.bound) {
      operationCloseButton.addEventListener("click", closeOperationModal);
      operationCloseButton.dataset.bound = "true";
    }

    if (operationForm && !operationForm.dataset.bound) {
      operationForm.addEventListener("submit", saveOperationModal);
      operationForm.addEventListener("focusout", (event) => {
        const field = event.target;
        if (!["amount", "amountHT", "vatRate", "vatAmount"].includes(field?.name)) return;
        if (field.value !== "" && Number.isFinite(Number(field.value))) {
          field.value = Number(field.value).toFixed(2);
        }
      });
      operationForm.dataset.bound = "true";
    }

    if (operationHideButton && !operationHideButton.dataset.bound) {
      operationHideButton.addEventListener("click", hideOperationFromModal);
      operationHideButton.dataset.bound = "true";
    }

    if (categoryAddButton && !categoryAddButton.dataset.bound) {
      categoryAddButton.addEventListener("click", addOperationCategory);
      categoryAddButton.dataset.bound = "true";
    }

    if (categoryForm && !categoryForm.dataset.bound) {
      categoryForm.addEventListener("submit", addCategoryFromSettings);
      categoryForm.dataset.bound = "true";
    }

    if (categoryList && !categoryList.dataset.bound) {
      categoryList.addEventListener("click", (event) => {
        const button = event.target.closest("[data-category-delete]");
        if (button) updateAccountingCategory("delete", button.dataset.categoryDelete);
      });
      categoryList.dataset.bound = "true";
    }

    if (operationModal && !operationModal.dataset.bound) {
      operationModal.addEventListener("click", (event) => {
        if (event.target === operationModal) closeOperationModal();
      });
      operationModal.dataset.bound = "true";
    }

    if (!document.body.dataset.accountingMenuBound) {
      document.addEventListener("click", (event) => {
        if (!event.target.closest(".accounting-action-cell")) {
          closeOperationMenus();
        }
      });
      document.body.dataset.accountingMenuBound = "true";
    }
  }

  function toggleSettingsPanel() {
    if (!settingsPanel || !settingsButton) return;
    const isHidden = settingsPanel.classList.toggle("is-hidden");
    settingsButton.setAttribute("aria-expanded", String(!isHidden));
  }

  function handlePowensCallback() {
    const url = new URL(window.location.href);
    const hasPowensParams = url.searchParams.has("connection_id")
      || url.searchParams.has("connection_ids")
      || url.searchParams.has("error")
      || url.searchParams.has("state");

    if (!hasPowensParams) return;

    if (url.searchParams.has("error")) {
      setStatus(`Connexion Powens interrompue : ${url.searchParams.get("error_description") || url.searchParams.get("error")}`, "error");
      return;
    }

    setStatus("Banque connectée. Synchronisation des données...", "success");
    window.history.replaceState({}, "", "/comptabilite.html");
  }

  async function connectPowens() {
    setLoading(true);
    setStatus("");

    try {
      const redirectUrl = getPowensRedirectUrl();
      const response = await functions.httpsCallable("powensCreateAccountingLink")({ redirectUrl });
      const url = response?.data?.url;

      if (!url) {
        throw new Error("Powens n'a pas renvoyé d'URL de connexion.");
      }

      window.location.href = url;
    } catch (error) {
      setLoading(false);
      setStatus(getReadableError(error), "error");
    }
  }

  function getPowensRedirectUrl() {
    const localHosts = new Set(["localhost", "127.0.0.1"]);

    if (localHosts.has(window.location.hostname)) {
      return "https://admin.flechemoica.fr/comptabilite.html";
    }

    return `${window.location.origin}/comptabilite.html`;
  }

  async function loadAccountingData(options = {}) {
    const isRefresh = Boolean(options.forceRefresh);
    setLoading(true);
    setStatus("");

    try {
      const response = await functions.httpsCallable("powensAccountingData")({
        forceRefresh: isRefresh,
      });

      if (!started) return;
      const data = response.data || {};
      renderAccountingData(data);
      setStatus("");
    } catch (error) {
      setStatus(getReadableError(error), "error");
    } finally {
      setLoading(false);
    }
  }

  async function refreshAccountingData() {
    if (refreshPromise) return refreshPromise;

    if (!started) {
      setStatus("La vue comptabilité n’est pas active.", "error");
      return;
    }

    console.info("Actualisation des comptes Powens demandée.");
    refreshPromise = loadAccountingData({ forceRefresh: true });

    try {
      await refreshPromise;
    } finally {
      refreshPromise = null;
    }
  }

  function renderAccountingData(data) {
    const accounts = Array.isArray(data.accounts) ? data.accounts : [];
    const transactions = Array.isArray(data.transactions) ? data.transactions : [];
    const hiddenTransactions = Array.isArray(data.hiddenTransactions) ? data.hiddenTransactions : [];
    const connected = Boolean(data.connected);

    if (connectionTitle) {
      connectionTitle.textContent = connected ? "Powens connecté" : "Aucune banque connectée";
    }

    if (connectionDetail) {
      connectionDetail.textContent = connected
        ? `${accounts.length} compte(s) synchronisé(s).`
        : "Connecte Revolut ou une autre banque pour importer les soldes et les dernières opérations.";
    }

    renderSummary(accounts, transactions, data.syncedAt);
    renderAccounts(accounts);
    currentTransactions = transactions;
    currentHiddenTransactions = hiddenTransactions;
    customCategories.clear();
    (data.settings?.categories || []).forEach((category) => customCategories.add(category));
    deletedCategories.clear();
    (data.settings?.deletedCategories || []).forEach((category) => deletedCategories.add(category));
    renderCategoryOptions([...transactions, ...hiddenTransactions]);
    renderCategoryManager([...transactions, ...hiddenTransactions]);
    renderHiddenOperations(hiddenTransactions);
    renderTransactions(transactions);
    void reconcileInvoicePayments(transactions);
  }

  async function reconcileInvoicePayments(transactions) {
    if (reconciliationPromise || !started || !transactions.length || typeof InvoicingView === "undefined" || !InvoicingView.createInvoicePDFFile) return;

    reconciliationPromise = (async () => {
      const invoiceSnapshot = await firestore.collection("invoices").limit(200).get();
      const invoicesByNumber = new Map();
      invoiceSnapshot.docs.forEach((doc) => {
        const invoice = doc.data() || {};
        const number = normalizeInvoiceReference(invoice.number);
        if (number && invoice.status !== "paid_card") invoicesByNumber.set(number, { id: doc.id, ref: doc.ref, ...invoice });
      });

      const reconciledInvoices = new Set();
      for (const transaction of transactions) {
        if (transaction.documentKey || transaction.documentUrl || Number(transaction.amount || 0) <= 0) continue;
        const references = [transaction.rawLabel, transaction.label].map(normalizeInvoiceReference);
        const invoice = references.map((reference) => invoicesByNumber.get(reference)).find(Boolean);
        if (!invoice || reconciledInvoices.has(invoice.id)) continue;

        reconciledInvoices.add(invoice.id);
        setStatus(`Rapprochement automatique de ${invoice.number}…`);
        const transactionId = String(transaction.settingsTransactionId || transaction.id || "");
        const pdfFile = await InvoicingView.createInvoicePDFFile(invoice);
        const uploadedDocument = await uploadAccountingDocument(transactionId, pdfFile);
        const saved = await updateAccountingOperation({
          transactionId,
          documentKey: uploadedDocument.objectKey,
          documentName: uploadedDocument.fileName,
          documentContentType: uploadedDocument.contentType,
          documentStatus: "Présent",
          invoiceNumber: invoice.number,
          paymentMode: "Virement",
          linkedRecord: invoice.id,
        });
        if (!saved) throw new Error(`Le rapprochement de ${invoice.number} n’a pas pu être enregistré.`);

        await invoice.ref.set({
          status: "paid_bank",
          paymentMethod: "bank_transfer",
          bankTransactionID: transactionId,
          bankPaidAt: firebase.firestore.FieldValue.serverTimestamp(),
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        setStatus(`${invoice.number} rapprochée et marquée payée par virement.`, "success");
      }
    })().catch((error) => {
      setStatus(error.message || "Le rapprochement automatique des factures a échoué.", "error");
    }).finally(() => {
      reconciliationPromise = null;
    });

    await reconciliationPromise;
  }

  function normalizeInvoiceReference(value) {
    return String(value || "").trim().toLocaleUpperCase("fr-FR");
  }

  function renderCategoryOptions(transactions) {
    if (!categoryOptions) return;
    const categories = [...new Set(
      [
        "À catégoriser",
        ...transactions.map((transaction) => String(transaction.category || "").trim()),
        ...customCategories,
      ].filter((category) => category && !deletedCategories.has(category))
    )].sort((first, second) => first.localeCompare(second, "fr", { sensitivity: "base" }));

    const selectedCategory = categoryOptions.value;
    categoryOptions.innerHTML = categories
      .map((category) => `<option value="${escapeHTML(category)}">${escapeHTML(category)}</option>`)
      .join("");
    categoryOptions.value = selectedCategory || "À catégoriser";
  }

  function getAvailableCategories(transactions) {
    return [...new Set([
      "À catégoriser",
      ...transactions.map((transaction) => String(transaction.category || "").trim()),
      ...customCategories,
    ].filter((category) => category && !deletedCategories.has(category)))]
      .sort((first, second) => first.localeCompare(second, "fr", { sensitivity: "base" }));
  }

  function renderCategoryManager(transactions) {
    if (!categoryList) return;
    categoryList.innerHTML = getAvailableCategories(transactions).map((category) => `
      <span class="accounting-category-item">
        ${escapeHTML(category)}
        ${category === "À catégoriser" ? "" : `<button type="button" data-category-delete="${escapeHTML(category)}" aria-label="Supprimer ${escapeHTML(category)}" title="Supprimer">×</button>`}
      </span>
    `).join("");
  }

  async function addCategoryFromSettings(event) {
    event.preventDefault();
    const category = categoryNameInput?.value.trim();
    if (!category) return;
    const saved = await updateAccountingCategory("add", category);
    if (saved && categoryNameInput) categoryNameInput.value = "";
  }

  async function updateAccountingCategory(action, category) {
    if (!category) return false;
    setLoading(true);
    setStatus("");
    try {
      const response = await functions.httpsCallable("powensUpdateAccountingCategory")({ action, category });
      renderAccountingData(response.data || {});
      return true;
    } catch (error) {
      setStatus(getReadableError(error), "error");
      return false;
    } finally {
      setLoading(false);
    }
  }

  async function addOperationCategory() {
    const category = window.prompt("Nom de la nouvelle catégorie :")?.trim();
    if (!category) return;
    const saved = await updateAccountingCategory("add", category);
    if (saved) categoryOptions.value = category;
  }

  function renderSummary(accounts, transactions, syncedAt) {
    const eurAccounts = accounts.filter((account) => account.currency === "EUR");
    const balance = eurAccounts.reduce((sum, account) => sum + Number(account.balance || 0), 0);

    if (totalBalance) totalBalance.textContent = formatMoney(balance, "EUR");
    if (accountCount) accountCount.textContent = String(accounts.length);
    if (transactionCount) transactionCount.textContent = String(transactions.length);
    if (lastUpdate) {
      lastUpdate.textContent = syncedAt ? `MAJ ${formatDateTime(new Date(syncedAt))}` : "";
    }

  }

  function renderAccounts(accounts) {
    if (!accountList) return;

    if (!accounts.length) {
      accountList.innerHTML = `<div class="empty-state">Aucun compte bancaire chargé.</div>`;
      return;
    }

    accountList.innerHTML = accounts.map((account) => `
      <article class="accounting-account-card">
        <div>
          <strong>${escapeHTML(account.name || "Compte bancaire")}</strong>
          <span>${escapeHTML(account.bankName || "Banque")} · ${escapeHTML(account.type || "Compte")}</span>
        </div>
        <div class="accounting-account-actions">
          <strong>${formatMoney(account.balance, account.currency)}</strong>
          <button class="accounting-small-button" type="button" data-account-remove="${escapeHTML(account.id)}">Supprimer</button>
        </div>
      </article>
    `).join("");

    accountList.querySelectorAll("[data-account-remove]").forEach((button) => {
      button.addEventListener("click", () => hideAccountingAccount(button.dataset.accountRemove));
    });
  }

  async function hideAccountingAccount(accountId) {
    if (!accountId) return;
    setLoading(true);
    setStatus("");

    try {
      const response = await functions.httpsCallable("powensUpdateAccountingAccount")({
        accountId,
        hidden: true,
      });

      renderAccountingData(response.data || {});
    } catch (error) {
      setStatus(getReadableError(error), "error");
    } finally {
      setLoading(false);
    }
  }

  function renderHiddenOperations(transactions) {
    if (!hiddenOperationList) return;
    if (hiddenCount) {
      hiddenCount.textContent = transactions.length ? `${transactions.length} masquée(s)` : "";
    }

    if (!transactions.length) {
      hiddenOperationList.innerHTML = `<div class="empty-state">Aucune opération masquée.</div>`;
      return;
    }

    hiddenOperationList.innerHTML = transactions.map((transaction) => {
      const amount = Number(transaction.amount || 0);
      const tone = amount < 0 ? "debit" : "credit";

      return `
        <article class="accounting-account-card">
          <div>
            <strong>${escapeHTML(transaction.label || "Opération")}</strong>
            <span>${escapeHTML(formatDate(transaction.date))}</span>
          </div>
          <div class="accounting-account-actions">
            <strong class="amount-${tone}">${formatMoney(amount, transaction.currency || "EUR")}</strong>
            ${transaction.autoHidden
              ? `<span>Masquée automatiquement</span>`
              : `<button class="accounting-small-button" type="button" data-operation-unhide="${escapeHTML(transaction.settingsTransactionId || transaction.id)}">Réafficher</button>`}
          </div>
        </article>
      `;
    }).join("");

    hiddenOperationList.querySelectorAll("[data-operation-unhide]").forEach((button) => {
      button.addEventListener("click", () => unhideAccountingOperation(button.dataset.operationUnhide));
    });
  }

  async function unhideAccountingOperation(transactionId) {
    if (!transactionId) return;
    await updateAccountingOperation({ transactionId, hidden: false });
  }

  function renderTransactions(transactions) {
    if (!transactionsBody) return;
    const query = normalizeSearch(searchInput?.value || "");
    const periodStart = parseDateFilter(periodStartInput?.value, "start");
    const periodEnd = parseDateFilter(periodEndInput?.value, "end");
    const visibleTransactions = transactions.filter((transaction) => {
      const transactionDate = parseTransactionDate(transaction.date);
      const matchesQuery = !query || normalizeSearch([
        transaction.label,
        transaction.category,
        transaction.amount,
        transaction.date,
      ].join(" ")).includes(query);
      const matchesStart = !periodStart || (transactionDate && transactionDate >= periodStart);
      const matchesEnd = !periodEnd || (transactionDate && transactionDate <= periodEnd);

      return matchesQuery && matchesStart && matchesEnd;
    }).sort((first, second) => {
      const firstDate = parseTransactionDate(first.date)?.getTime() || 0;
      const secondDate = parseTransactionDate(second.date)?.getTime() || 0;
      return secondDate - firstDate;
    });

    if (!visibleTransactions.length) {
      transactionsBody.innerHTML = `<tr><td colspan="8">Aucune opération chargée pour cette période.</td></tr>`;
      return;
    }

    transactionsBody.innerHTML = visibleTransactions.map((transaction) => {
      const amount = Number(transaction.amount || 0);
      const tone = amount < 0 ? "debit" : "credit";
      const thirdParty = transaction.thirdParty || transaction.rawLabel || transaction.label || "—";
      const type = transaction.type || (amount < 0 ? "Dépense" : "Recette");

      return `
        <tr data-accounting-operation="${escapeHTML(transaction.id)}">
          <td>${escapeHTML(formatDate(transaction.date))}</td>
          <td><strong>${escapeHTML(thirdParty)}</strong></td>
          <td>${escapeHTML(type)}</td>
          <td>${escapeHTML(transaction.category || "À catégoriser")}</td>
          <td><strong>${escapeHTML(transaction.label || "Opération")}</strong></td>
          <td class="accounting-amount-cell"><strong class="amount-${tone}">${formatMoney(amount, transaction.currency || "EUR")}</strong></td>
          <td class="accounting-document-cell">${transaction.documentKey
            ? `<button class="accounting-document-link" type="button" data-document-key="${escapeHTML(transaction.documentKey)}" aria-label="Ouvrir la facture" title="Ouvrir la facture">📎</button>`
            : transaction.documentUrl
              ? `<a href="${escapeHTML(transaction.documentUrl)}" target="_blank" rel="noopener noreferrer" aria-label="Ouvrir la facture" title="Ouvrir la facture">📎</a>`
              : `<span class="accounting-document-missing" aria-label="Facture manquante" title="Facture manquante">×</span>`}
          </td>
          <td>${escapeHTML(transaction.status || "À vérifier")}</td>
        </tr>
      `;
    }).join("");

    transactionsBody.querySelectorAll("[data-operation-menu]").forEach((button) => {
      button.addEventListener("click", (event) => {
        event.stopPropagation();
        toggleOperationMenu(button.dataset.operationMenu);
      });
    });

    transactionsBody.querySelectorAll("[data-operation-action]").forEach((button) => {
      button.addEventListener("click", (event) => {
        event.stopPropagation();
        handleOperationAction(button.dataset.operationAction, button.dataset.operationId);
      });
    });

    transactionsBody.querySelectorAll("[data-accounting-operation]").forEach((row) => {
      row.addEventListener("click", (event) => {
        if (event.target.closest("button, a, .accounting-action-menu")) return;
        openOperationModal(row.dataset.accountingOperation);
      });
    });

    transactionsBody.querySelectorAll("[data-document-key]").forEach((button) => {
      button.addEventListener("click", (event) => {
        event.stopPropagation();
        openAccountingDocument(button.dataset.documentKey);
      });
    });
  }

  async function openAccountingDocument(objectKey) {
    const documentWindow = window.open("about:blank", "_blank");
    try {
      const response = await functions.httpsCallable("r2CreateAccountingDownloadUrl")({ objectKey });
      const downloadUrl = response?.data?.downloadUrl;
      if (!downloadUrl) throw new Error("Lien du justificatif introuvable.");
      if (documentWindow) documentWindow.location.href = downloadUrl;
      else window.open(downloadUrl, "_blank", "noopener");
    } catch (error) {
      documentWindow?.close();
      setStatus(getReadableError(error), "error");
    }
  }

  function openOperationModal(transactionId) {
    const transaction = currentTransactions.find(
      (item) => String(item.id || "") === String(transactionId || "")
    );
    if (!transaction || !operationModal || !operationForm) return;

    operationForm.reset();
    const values = {
      ...transaction,
      transactionId: transaction.settingsTransactionId || transaction.id,
      sourceId: transaction.sourceId || transaction.id,
      bankAccount: transaction.bankAccount || transaction.accountName,
      bankDate: normalizeDateInput(transaction.bankDate || transaction.date),
      date: normalizeDateInput(transaction.date),
      rawLabel: transaction.rawLabel || transaction.label,
      thirdParty: transaction.thirdParty || transaction.rawLabel || transaction.label,
      type: transaction.type || (Number(transaction.amount || 0) < 0 ? "Dépense" : "Recette"),
      direction: transaction.direction || (Number(transaction.amount || 0) < 0 ? "Débit" : "Crédit"),
      status: transaction.status || "À vérifier",
      category: transaction.category || "À catégoriser",
      documentStatus: transaction.documentStatus || "Manquant",
    };

    Array.from(operationForm.elements).forEach((field) => {
      if (!field.name || field.type === "submit" || field.type === "button") return;
      const value = values[field.name];
      const usesTwoDecimals = ["amount", "amountHT", "vatRate", "vatAmount"].includes(field.name);
      field.value = value === null || value === undefined || value === ""
        ? ""
        : usesTwoDecimals && Number.isFinite(Number(value))
          ? Number(value).toFixed(2)
          : String(value);
    });

    operationModal.classList.remove("is-hidden");
    document.body.classList.add("modal-open");
  }

  function closeOperationModal() {
    operationModal?.classList.add("is-hidden");
    document.body.classList.remove("modal-open");
  }

  async function saveOperationModal(event) {
    event.preventDefault();
    if (!operationForm) return;

    try {
      const payload = Object.fromEntries(new FormData(operationForm).entries());
      delete payload.bankDate;
      delete payload.rawLabel;
      delete payload.documentFile;

      const selectedFile = operationForm.elements?.documentFile?.files?.[0];
      const currentTransaction = currentTransactions.find(
        (transaction) => String(transaction.settingsTransactionId || transaction.id) === String(payload.transactionId)
      );
      if (payload.status === "Validée" && !selectedFile && !currentTransaction?.documentKey && !currentTransaction?.documentUrl) {
        throw new Error("Ajoute un justificatif avant de valider cette opération.");
      }

      const uploadedDocument = await uploadOperationDocument(payload.transactionId);
      if (uploadedDocument) {
        payload.documentKey = uploadedDocument.objectKey;
        payload.documentName = uploadedDocument.fileName;
        payload.documentContentType = uploadedDocument.contentType;
        payload.documentStatus = "Présent";
      }

      const saved = await updateAccountingOperation(payload);
      if (saved) {
        if (payload.category) customCategories.add(payload.category);
        renderCategoryOptions([...currentTransactions, ...currentHiddenTransactions]);
        closeOperationModal();
      }
    } catch (error) {
      setStatus(getReadableError(error), "error");
    }
  }

  async function uploadOperationDocument(transactionId) {
    const fileInput = operationForm?.elements?.documentFile;
    const file = fileInput?.files?.[0];
    if (!file) return null;

    const allowedType = file.type === "application/pdf" || file.type.startsWith("image/");
    if (!allowedType) {
      throw new Error("Le justificatif doit être un PDF ou une image.");
    }

    if (file.size > 10 * 1024 * 1024) {
      throw new Error("Le justificatif ne doit pas dépasser 10 Mo.");
    }

    return uploadAccountingDocument(transactionId, file);
  }

  async function uploadAccountingDocument(transactionId, file) {
    const response = await functions.httpsCallable("r2CreateAccountingUploadUrl")({
      transactionId,
      fileName: file.name || "justificatif",
      contentType: file.type,
      fileSize: file.size,
    });
    const uploadData = response?.data || {};
    if (!uploadData.uploadUrl || !uploadData.objectKey) {
      throw new Error("Cloudflare R2 n’a pas fourni de lien d’import.");
    }

    const uploadResponse = await fetch(uploadData.uploadUrl, {
      method: "PUT",
      headers: { "Content-Type": file.type },
      body: file,
    });
    if (!uploadResponse.ok) {
      throw new Error(`Import du justificatif impossible (${uploadResponse.status}).`);
    }
    return uploadData;
  }

  async function hideOperationFromModal() {
    const transactionId = operationForm?.elements?.transactionId?.value;
    if (!transactionId) return;
    const saved = await updateAccountingOperation({ transactionId, hidden: true });
    if (saved) closeOperationModal();
  }

  function toggleOperationMenu(transactionId) {
    const panel = transactionsBody?.querySelector(`[data-operation-menu-panel="${cssEscape(transactionId)}"]`);
    if (!panel) return;
    const wasHidden = panel.classList.contains("is-hidden");
    closeOperationMenus();
    panel.classList.toggle("is-hidden", !wasHidden);
  }

  function closeOperationMenus() {
    document.querySelectorAll(".accounting-action-menu").forEach((menu) => {
      menu.classList.add("is-hidden");
    });
  }

  async function handleOperationAction(action, transactionId) {
    const transaction = currentTransactions.find((item) => String(item.id) === String(transactionId));
    if (!transaction) return;
    closeOperationMenus();

    const payload = { transactionId };

    if (action === "rename") {
      const label = window.prompt("Nouveau libellé", transaction.label || "");
      if (label === null) return;
      payload.label = label.trim();
    } else if (action === "date") {
      const currentDate = normalizeDateInput(transaction.date);
      const date = window.prompt("Nouvelle date (AAAA-MM-JJ)", currentDate);
      if (date === null) return;
      payload.date = date.trim();
    } else if (action === "hide") {
      payload.hidden = true;
    } else {
      return;
    }

    await updateAccountingOperation(payload);
  }

  async function updateAccountingOperation(payload) {
    setLoading(true);
    setStatus("");

    try {
      const response = await functions.httpsCallable("powensUpdateAccountingOperation")(payload);
      renderAccountingData(response.data || {});
      return true;
    } catch (error) {
      setStatus(getReadableError(error), "error");
      return false;
    } finally {
      setLoading(false);
    }
  }

  function normalizeDateInput(value) {
    if (!value) return "";
    const date = new Date(value);
    if (!Number.isFinite(date.getTime())) return String(value).slice(0, 10);
    return date.toISOString().slice(0, 10);
  }

  function formatDateInputLocal(date) {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, "0");
    const day = String(date.getDate()).padStart(2, "0");
    return `${year}-${month}-${day}`;
  }

  function parseDateFilter(value, boundary) {
    if (!value) return null;
    const date = new Date(`${value}T${boundary === "end" ? "23:59:59" : "00:00:00"}`);
    return Number.isFinite(date.getTime()) ? date : null;
  }

  function parseTransactionDate(value) {
    if (!value) return null;
    const date = new Date(value);
    return Number.isFinite(date.getTime()) ? date : null;
  }

  function cssEscape(value) {
    if (window.CSS && typeof window.CSS.escape === "function") {
      return window.CSS.escape(String(value || ""));
    }

    return String(value || "").replace(/"/g, "\\\"");
  }

  function normalizeSearch(value) {
    return String(value || "")
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .trim();
  }

  function setLoading(isLoading) {
    [connectButton, connectCardButton, refreshButton, settingsButton].forEach((button) => {
      if (button) button.disabled = isLoading;
    });
  }

  function setStatus(message, tone = "") {
    if (!statusNode) return;
    statusNode.textContent = message;
    statusNode.dataset.tone = tone;
  }

  function getReadableError(error) {
    console.error("Erreur comptabilité Powens", error);

    const code = String(error?.code || "");
    const message = error?.message || "Erreur inconnue.";
    const details = error?.details || {};
    const status = Number(details.status || 0);

    if (message.includes("POWENS_CLIENT_SECRET")) {
      return "Secret Powens manquant côté Firebase Functions : configure POWENS_CLIENT_SECRET avant de connecter la banque.";
    }

    if (message.includes("POWENS_CLIENT_ID")) {
      return "Client ID Powens manquant côté Firebase Functions.";
    }

    if (code.includes("not-found") || status === 404) {
      return "Fonctions Powens non déployées : déploie les Cloud Functions avant de connecter la banque.";
    }

    if (code.includes("internal")) {
      return message === "internal"
        ? "Erreur serveur Firebase Functions. Vérifie que les fonctions Powens sont déployées et que le secret POWENS_CLIENT_SECRET est configuré."
        : message;
    }

    return message;
  }

  function formatMoney(value, currency = "EUR") {
    const amount = Number(value || 0);
    return new Intl.NumberFormat("fr-FR", {
      style: "currency",
      currency: currency || "EUR",
    }).format(amount);
  }

  function formatDate(value) {
    if (!value) return "";
    const date = new Date(value);
    if (!Number.isFinite(date.getTime())) return String(value);
    return new Intl.DateTimeFormat("fr-FR", { day: "2-digit", month: "2-digit", year: "numeric" }).format(date);
  }

  function formatDateTime(date) {
    return new Intl.DateTimeFormat("fr-FR", {
      day: "2-digit",
      month: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
    }).format(date);
  }

  function escapeHTML(value) {
    return String(value ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  return {
    init,
    start,
    stop,
  };
})();
