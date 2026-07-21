const InvoicingView = (() => {
  let firestore = null;
  let functions = null;
  let started = false;
  let loaded = false;
  let loadPromise = null;
  let settings = {};
  let sponsoredCampaigns = [];
  let editingInvoiceID = "";
  let unsubscribe = null;
  const TAX_MENTION = "TVA non applicable, art. 293 B du CGI.";
  const OPERATION_NATURE = "Prestation de services";

  function legalMentions(invoice) {
    return [
      TAX_MENTION,
      `Nature de l’opération : ${invoice.operationNature || OPERATION_NATURE}.`,
      "Escompte pour paiement anticipé : néant.",
      "Pénalités de retard : taux directeur semestriel de la BCE majoré de 10 points, exigibles dès le lendemain de la date d’échéance.",
      "En cas de retard de paiement, indemnité forfaitaire de 40 € pour frais de recouvrement.",
    ];
  }

  function init() {}

  async function start() {
    started = true;
    await ensureView();
    if (!started) return;
    firestore = firebase.firestore();
    functions = firebase.app().functions("europe-west1");
    bindEvents();
    await loadSettings();
    listenInvoices();
  }

  function stop() {
    started = false;
    if (unsubscribe) unsubscribe();
    unsubscribe = null;
  }

  async function ensureView() {
    if (loaded) return;
    if (!loadPromise) {
      loadPromise = fetch("/views/facturation.html", { cache: "no-store" })
        .then((response) => {
          if (!response.ok) throw new Error("Impossible de charger la facturation.");
          return response.text();
        })
        .then((html) => {
          document.getElementById("invoicing-panel").innerHTML = html;
          loaded = true;
        });
    }
    await loadPromise;
  }

  function bindEvents() {
    const panel = document.getElementById("invoicing-panel");
    if (panel.dataset.bound === "true") return;
    panel.dataset.bound = "true";
    node("invoice-settings-toggle").addEventListener("click", () => togglePanel("invoice-settings-panel"));
    node("new-invoice-button").addEventListener("click", openInvoiceEditor);
    node("cancel-invoice-button").addEventListener("click", () => node("invoice-editor-panel").classList.add("is-hidden"));
    node("add-invoice-line").addEventListener("click", openLineChoice);
    node("invoice-line-choice-form").addEventListener("submit", confirmLineChoice);
    node("invoice-settings-form").addEventListener("submit", saveSettings);
    node("invoice-form").addEventListener("submit", saveInvoice);
    node("invoice-form").elements.issueDate.addEventListener("change", () => syncDueDateMinimum(true));
    node("invoice-form").elements.clientType.addEventListener("change", syncClientTypeFields);
    node("invoice-form").elements.clientCountry.addEventListener("input", syncClientTypeFields);
    node("invoice-lines").addEventListener("input", updateTotals);
    node("invoice-lines").addEventListener("click", (event) => {
      const button = event.target.closest("[data-remove-invoice-line]");
      if (!button) return;
      button.closest(".invoice-line").remove();
      updateTotals();
    });
    node("invoice-list-body").addEventListener("click", (event) => {
      const button = event.target.closest("[data-invoice-pdf]");
      if (button) generateInvoicePDF(button.dataset.invoicePdf);
      const deleteButton = event.target.closest("[data-delete-invoice]");
      if (deleteButton) deleteInvoice(deleteButton.dataset.deleteInvoice);
      const editButton = event.target.closest("[data-edit-invoice]");
      if (editButton) editInvoice(editButton.dataset.editInvoice);
    });
  }

  function syncDueDateMinimum(resetToDefault = false) {
    const form = node("invoice-form");
    const issueDate = form.elements.issueDate.value;
    const dueDate = form.elements.dueDate;
    dueDate.min = issueDate;
    if (resetToDefault || !dueDate.value || dueDate.value < issueDate) dueDate.value = addDaysToISODate(issueDate, 15);
  }

  function syncClientTypeFields() {
    const form = node("invoice-form");
    const professional = form.elements.clientType.value === "professional";
    const frenchProfessional = professional && /^(fr|france)$/i.test(form.elements.clientCountry.value.trim());
    const field = node("invoice-client-siren-field");
    field.hidden = !frenchProfessional;
    form.elements.clientSiren.required = frenchProfessional;
    if (!frenchProfessional) form.elements.clientSiren.value = "";
  }

  function clientSiren(invoice) {
    if (invoice.clientType === "individual") return "";
    return String(invoice.clientSiren || invoice.clientSiret || "").replace(/\D/g, "").slice(0, 9);
  }

  async function loadSettings() {
    const snapshot = await firestore.collection("invoiceSettings").doc("default").get();
    settings = snapshot.data() || { tradeName: "FLÈCHE-MOI ÇA", email: "contact@flechemoica.fr", legalForm: "Entrepreneur individuel", country: "France", invoicePrefix: "FMC", nextInvoiceNumber: 1 };
    const form = node("invoice-settings-form");
    Object.entries(settings).forEach(([key, value]) => {
      if (form.elements[key] && typeof value !== "object") {
        if (form.elements[key].type === "checkbox") form.elements[key].checked = isEnabled(value);
        else form.elements[key].value = value ?? "";
      }
    });
  }

  async function saveSettings(event) {
    event.preventDefault();
    const form = event.currentTarget;
    const data = Object.fromEntries(new FormData(form).entries());
    data.paypalEnabled = form.elements.paypalEnabled.checked;
    data.nextInvoiceNumber = Math.max(1, Number(data.nextInvoiceNumber || 1));
    data.updatedAt = firebase.firestore.FieldValue.serverTimestamp();
    setStatus("Enregistrement…");
    await firestore.collection("invoiceSettings").doc("default").set(data, { merge: true });
    settings = { ...settings, ...data };
    setStatus("Réglages enregistrés.", "success");
  }

  function openInvoiceEditor() {
    editingInvoiceID = "";
    const form = node("invoice-form");
    form.reset();
    const today = new Date();
    form.elements.issueDate.value = isoDate(today);
    form.elements.dueDate.value = addDaysToISODate(form.elements.issueDate.value, 15);
    syncDueDateMinimum();
    form.elements.clientCountry.value = "France";
    form.elements.currency.value = "EUR";
    form.elements.clientType.value = "individual";
    syncClientTypeFields();
    form.elements.status.value = "created";
    form.elements.paypalEnabled.checked = isEnabled(settings.paypalEnabled);
    form.elements.number.value = nextNumber();
    node("invoice-lines").innerHTML = "";
    updateTotals();
    node("invoice-editor-panel").classList.remove("is-hidden");
    node("invoice-editor-title").textContent = "Nouvelle facture client";
    node("invoice-editor-panel").scrollIntoView({ behavior: "smooth", block: "start" });
  }

  async function editInvoice(invoiceID) {
    const snapshot = await firestore.collection("invoices").doc(invoiceID).get();
    if (!snapshot.exists) {
      setStatus("Facture introuvable.", "error");
      return;
    }
    editingInvoiceID = invoiceID;
    const invoice = snapshot.data();
    const form = node("invoice-form");
    form.reset();
    ["number", "issueDate", "dueDate", "currency", "clientName", "clientSecondaryLine", "clientAddress", "clientPostalCode", "clientCity", "clientCountry", "clientEmail"].forEach((key) => {
      if (form.elements[key]) form.elements[key].value = invoice[key] || "";
    });
    form.elements.clientType.value = invoice.clientType || ((invoice.clientSiren || invoice.clientSiret) ? "professional" : "individual");
    form.elements.clientSiren.value = invoice.clientSiren || String(invoice.clientSiret || "").replace(/\D/g, "").slice(0, 9);
    syncClientTypeFields();
    form.elements.status.value = ({ draft: "created", validated: "sent" }[invoice.status] || invoice.status || "created");
    if (!form.elements.dueDate.value) form.elements.dueDate.value = addDaysToISODate(invoice.issueDate || isoDate(new Date()), 15);
    syncDueDateMinimum();
    form.elements.paypalEnabled.checked = isEnabled(invoice.paypalEnabled ?? invoice.issuerSnapshot?.paypalEnabled);
    node("invoice-lines").innerHTML = "";
    (invoice.lines || []).forEach(addLine);
    updateTotals();
    node("invoice-editor-title").textContent = `Modifier ${invoice.number || "la facture"}`;
    node("invoice-editor-panel").classList.remove("is-hidden");
    node("invoice-editor-panel").scrollIntoView({ behavior: "smooth", block: "start" });
  }

  function nextNumber() {
    const prefix = String(settings.invoicePrefix || "FMC").trim();
    const sequence = String(Math.max(1, Number(settings.nextInvoiceNumber || 1))).padStart(4, "0");
    return `${prefix}-${new Date().getFullYear()}-${sequence}`;
  }

  function addLine(line = {}) {
    const row = document.createElement("div");
    row.className = "invoice-line";
    row.innerHTML = `
      <label>Description<input data-line="description" required value="${escapeAttribute(line.description || "")}"></label>
      <label>Quantité<input data-line="quantity" type="number" min="0.01" step="0.01" value="${line.quantity || 1}" required></label>
      <label>Prix unitaire HT<input data-line="unitPrice" type="number" min="0" step="0.01" value="${line.unitPrice || ""}" required></label>
      <button class="icon-action-button danger-button" data-remove-invoice-line type="button" aria-label="Supprimer la ligne">×</button>`;
    node("invoice-lines").appendChild(row);
    updateTotals();
  }

  async function openLineChoice() {
    const select = node("invoice-line-source");
    select.innerHTML = '<option value="other">Autre — ligne vide</option>';
    try {
      const snapshot = await firestore.collection("homeCommunications").get();
      sponsoredCampaigns = snapshot.docs
        .map((doc) => ({ id: doc.id, ...doc.data() }))
        .filter((campaign) => campaign.type === "sponsored");
      sponsoredCampaigns.forEach((campaign) => {
        const option = document.createElement("option");
        option.value = campaign.id;
        option.textContent = campaign.clientName
          ? `Campagne publicitaire horaire — ${campaign.clientName}`
          : `Campagne publicitaire horaire — ${campaign.id}`;
        select.appendChild(option);
      });
    } catch (error) {
      setStatus(error.message || "Impossible de charger les campagnes.", "error");
    }
    node("invoice-line-dialog").showModal();
  }

  function confirmLineChoice(event) {
    const submitter = event.submitter;
    if (!submitter || submitter.value === "cancel") return;
    event.preventDefault();
    const campaignID = node("invoice-line-source").value;
    if (campaignID === "other") {
      addLine();
      syncDueDateMinimum();
    } else {
      const campaign = sponsoredCampaigns.find((item) => item.id === campaignID);
      if (campaign) {
        linesFromCampaign(campaign).forEach(addLine);
        setDueDateFromCampaign(campaign);
      }
    }
    node("invoice-line-dialog").close();
  }

  function setDueDateFromCampaign(campaign) {
    const periods = Array.isArray(campaign.displayPeriods) && campaign.displayPeriods.length
      ? campaign.displayPeriods
      : (campaign.startsAt || campaign.endsAt ? [{ startsAt: campaign.startsAt, endsAt: campaign.endsAt }] : []);
    const ends = periods
      .map((period) => firestoreDate(period.endsAt))
      .filter(Boolean)
      .sort((first, second) => first.getTime() - second.getTime());
    if (!ends.length) {
      syncDueDateMinimum();
      return;
    }
    node("invoice-form").elements.dueDate.value = addDaysToISODate(isoDate(ends[ends.length - 1]), 15);
  }

  function linesFromCampaign(campaign) {
    const periods = Array.isArray(campaign.displayPeriods) && campaign.displayPeriods.length
      ? campaign.displayPeriods
      : (campaign.startsAt || campaign.endsAt ? [{ startsAt: campaign.startsAt, endsAt: campaign.endsAt }] : []);
    if (!periods.length) {
      return [{ description: "Campagne publicitaire horaire — dates non renseignées", quantity: 1, unitPrice: "" }];
    }
    return periods.map((period) => {
      const start = firestoreDate(period.startsAt);
      const end = firestoreDate(period.endsAt);
      const hours = start && end ? Math.max(0, (end.getTime() - start.getTime()) / 3600000) : 0;
      const dates = start && end ? `du ${formatDateTime(start)} au ${formatDateTime(end)}` : "dates non renseignées";
      return {
        description: `Campagne publicitaire horaire — ${dates}`,
        quantity: round(hours) || 1,
        unitPrice: "",
      };
    });
  }

  function readLines() {
    return Array.from(node("invoice-lines").querySelectorAll(".invoice-line")).map((row) => {
      const get = (name) => row.querySelector(`[data-line="${name}"]`).value;
      const quantity = Number(get("quantity") || 0);
      const unitPrice = Number(get("unitPrice") || 0);
      const vatRate = 0;
      const totalExTax = round(quantity * unitPrice);
      const vatAmount = round(totalExTax * vatRate / 100);
      return { description: get("description").trim(), quantity, unitPrice, vatRate, totalExTax, vatAmount, totalIncTax: round(totalExTax + vatAmount) };
    });
  }

  function totals(lines = readLines()) {
    return lines.reduce((sum, line) => ({
      totalExTax: round(sum.totalExTax + line.totalExTax),
      totalVat: round(sum.totalVat + line.vatAmount),
      totalIncTax: round(sum.totalIncTax + line.totalIncTax),
    }), { totalExTax: 0, totalVat: 0, totalIncTax: 0 });
  }

  function updateTotals() {
    const value = totals();
    node("invoice-total-ex-tax").textContent = money(value.totalExTax);
    node("invoice-total-vat").textContent = money(value.totalVat);
    node("invoice-total-inc-tax").textContent = money(value.totalIncTax);
  }

  async function saveInvoice(event) {
    event.preventDefault();
    if (!settings.legalName || !settings.address || !settings.legalForm) {
      setStatus("Complète d’abord les réglages de l’émetteur.", "error");
      node("invoice-settings-panel").classList.remove("is-hidden");
      return;
    }
    const form = event.currentTarget;
    const formData = Object.fromEntries(new FormData(form).entries());
    formData.clientSiren = String(formData.clientSiren || "").replace(/\D/g, "");
    const frenchProfessional = formData.clientType === "professional" && /^(fr|france)$/i.test(String(formData.clientCountry || "").trim());
    if (frenchProfessional && formData.clientSiren.length !== 9) {
      setStatus("Le SIREN du client professionnel doit comporter 9 chiffres.", "error");
      form.elements.clientSiren.focus();
      return;
    }
    if (!frenchProfessional) formData.clientSiren = "";
    const lines = readLines();
    if (!lines.length || lines.some((line) => !line.description || line.quantity <= 0)) {
      setStatus("Ajoute au moins une ligne valide.", "error");
      return;
    }
    const invoiceTotals = totals(lines);
    const invoice = {
      ...formData,
      paypalEnabled: form.elements.paypalEnabled.checked,
      lines,
      ...invoiceTotals,
      status: ["created", "sent", "paid_card", "paid_bank"].includes(formData.status) ? formData.status : "created",
      operationCategory: "service",
      operationNature: OPERATION_NATURE,
      taxMention: TAX_MENTION,
      issuerSnapshot: { ...settings, updatedAt: null },
      createdAt: firebase.firestore.FieldValue.serverTimestamp(),
      updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
    };
    setStatus("Création de la facture…");
    if (editingInvoiceID) {
      delete invoice.createdAt;
      invoice.paypalOrderID = firebase.firestore.FieldValue.delete();
      invoice.paypalPaymentUrl = firebase.firestore.FieldValue.delete();
      invoice.paypalPaymentStatus = firebase.firestore.FieldValue.delete();
      invoice.paypalPaymentCreatedAt = firebase.firestore.FieldValue.delete();
      invoice.paypalPaymentToken = firebase.firestore.FieldValue.delete();
      invoice.paypalPaymentType = firebase.firestore.FieldValue.delete();
      await firestore.collection("invoices").doc(editingInvoiceID).set(invoice, { merge: true });
    } else {
      const batch = firestore.batch();
      batch.set(firestore.collection("invoices").doc(), invoice);
      batch.set(firestore.collection("invoiceSettings").doc("default"), {
        nextInvoiceNumber: Math.max(1, Number(settings.nextInvoiceNumber || 1)) + 1,
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      await batch.commit();
      settings.nextInvoiceNumber = Math.max(1, Number(settings.nextInvoiceNumber || 1)) + 1;
    }
    editingInvoiceID = "";
    node("invoice-editor-panel").classList.add("is-hidden");
    setStatus("Facture enregistrée.", "success");
  }

  function listenInvoices() {
    if (unsubscribe) unsubscribe();
    unsubscribe = firestore.collection("invoices").orderBy("createdAt", "desc").limit(100).onSnapshot((snapshot) => {
      const body = node("invoice-list-body");
      if (snapshot.empty) {
        body.innerHTML = '<tr><td colspan="6">Aucune facture.</td></tr>';
        return;
      }
      body.innerHTML = snapshot.docs.map((doc) => {
        const invoice = doc.data();
        const statusLabel = invoice.paypalPaymentStatus === "COMPLETED" ? "Payée (carte)" : ({
          draft: "Créée",
          created: "Créée",
          validated: "Envoyée",
          sent: "Envoyée",
          paid_card: "Payée (carte)",
          paid_bank: "Payée (virement)",
        }[invoice.status] || "Créée");
        return `<tr><td>${escapeHTML(invoice.number || "")}</td><td>${escapeHTML(formatDate(invoice.issueDate))}</td><td>${escapeHTML(invoice.clientName || "")}</td><td>${money(invoice.totalIncTax || 0)}</td><td><span class="accounting-pill">${statusLabel}</span></td><td><div class="invoice-row-actions"><button class="ghost-button invoice-pdf-button" type="button" data-invoice-pdf="${escapeAttribute(doc.id)}">PDF</button><button class="icon-action-button" type="button" data-edit-invoice="${escapeAttribute(doc.id)}" aria-label="Modifier la facture" title="Modifier">✎</button><button class="icon-action-button danger-button" type="button" data-delete-invoice="${escapeAttribute(doc.id)}" aria-label="Supprimer la facture" title="Supprimer">×</button></div></td></tr>`;
      }).join("");
    }, (error) => setStatus(error.message || "Impossible de charger les factures.", "error"));
  }

  async function deleteInvoice(invoiceID) {
    const snapshot = await firestore.collection("invoices").doc(invoiceID).get();
    const number = snapshot.data()?.number || "cette facture";
    if (!window.confirm(`Supprimer définitivement ${number} ?`)) return;
    setStatus("Suppression de la facture…");
    await firestore.collection("invoices").doc(invoiceID).delete();
    setStatus("Facture supprimée.", "success");
  }

  async function generateInvoicePDF(invoiceID) {
    try {
      setStatus("Préparation du PDF…");
      const snapshot = await firestore.collection("invoices").doc(invoiceID).get();
      if (!snapshot.exists) throw new Error("Facture introuvable.");
      const invoice = snapshot.data();
      if (isEnabled(invoice.paypalEnabled ?? invoice.issuerSnapshot?.paypalEnabled)) {
        setStatus("Création du lien de paiement…");
        const result = await functions.httpsCallable("createPaypalInvoicePayment")({ invoiceID });
        invoice.paypalPaymentUrl = result.data.paymentUrl;
        invoice.paypalPaymentType = "checkout";
      }
      await downloadInvoicePDF(invoice);
      setStatus("PDF téléchargé.", "success");
    } catch (error) {
      setStatus(error.message || "Impossible de générer le PDF.", "error");
    }
  }

  async function downloadInvoicePDF(invoice) {
    const { doc, filename } = await buildInvoicePDF(invoice);
    doc.save(filename);
  }

  async function createInvoicePDFFile(invoice) {
    const { doc, filename } = await buildInvoicePDF(invoice);
    return new File([doc.output("blob")], filename, { type: "application/pdf" });
  }

  async function buildInvoicePDF(invoice) {
    if (!window.jspdf?.jsPDF) throw new Error("Le générateur PDF n’est pas disponible. Recharge la page.");
    const { jsPDF } = window.jspdf;
    const doc = new jsPDF({ orientation: "portrait", unit: "mm", format: "a4" });
    const issuer = invoice.issuerSnapshot || {};
    const violet = [192, 174, 238];
    const dark = [35, 48, 68];
    const muted = [102, 112, 133];
    const pale = [243, 240, 252];
    const left = 18;
    const right = 192;
    const width = right - left;

    try {
      const logoResponse = await fetch("/assets/img/flechemoica-logo.png", { cache: "force-cache" });
      const logoBlob = await logoResponse.blob();
      const logoData = await blobDataURL(logoBlob);
      doc.addImage(logoData, "PNG", left, 15, 15, 15);
    } catch (_error) {}

    doc.setTextColor(...dark);
    drawPDFBrandTitle(doc, String(issuer.tradeName || "FLÈCHE-MOI ÇA"), 38, 17, dark);
    doc.setTextColor(...violet);
    doc.setFont("helvetica", "bold");
    doc.setFontSize(8);
    doc.text("FACTURE", 38, 28);
    doc.setTextColor(...dark);
    doc.setFontSize(12);
    doc.text(String(invoice.number || ""), right, 21, { align: "right" });
    doc.setTextColor(...muted);
    doc.setFont("helvetica", "normal");
    doc.setFontSize(8);
    doc.text(`Émise le ${formatDate(invoice.issueDate)}`, right, 27, { align: "right" });
    doc.text(`Échéance le ${formatDate(invoice.dueDate || invoice.issueDate)}`, right, 31, { align: "right" });
    doc.setDrawColor(...violet);
    doc.setLineWidth(0.8);
    doc.line(left, 34, right, 34);

    drawPDFParty(doc, left, 42, 84, "ÉMETTEUR", [
      issuer.tradeName || "FLÈCHE-MOI ÇA",
      [issuer.legalName, issuer.legalForm].filter(Boolean).join(" — "),
      issuer.address,
      issuer.addressExtra,
      [issuer.postalCode, issuer.city].filter(Boolean).join(" "),
      issuer.country,
      [issuer.siren ? `SIREN : ${issuer.siren}` : "", issuer.siret ? `SIRET : ${issuer.siret}` : ""].filter(Boolean).join(" · "),
      issuer.email,
    ]);
    drawPDFParty(doc, 108, 42, 84, "CLIENT", [
      invoice.clientName,
      invoice.clientSecondaryLine,
      invoice.clientAddress,
      [invoice.clientPostalCode, invoice.clientCity].filter(Boolean).join(" "),
      invoice.clientCountry,
      clientSiren(invoice) ? `SIREN : ${clientSiren(invoice)}` : "",
      invoice.clientEmail,
    ]);

    let y = 91;
    doc.setFillColor(...dark);
    doc.rect(left, y, width, 10, "F");
    doc.setTextColor(255, 255, 255);
    doc.setFont("helvetica", "bold");
    doc.setFontSize(8);
    doc.text("Description", left + 3, y + 6.5);
    doc.text("Quantité", 132, y + 6.5, { align: "right" });
    doc.text("Prix unitaire HT", 161, y + 6.5, { align: "right" });
    doc.text("Total HT", right - 3, y + 6.5, { align: "right" });
    y += 10;
    doc.setTextColor(...dark);
    doc.setFont("helvetica", "normal");
    (invoice.lines || []).forEach((line) => {
      const description = doc.splitTextToSize(String(line.description || ""), 88);
      const rowHeight = Math.max(10, description.length * 4.2 + 4);
      doc.setDrawColor(227, 231, 237);
      doc.line(left, y + rowHeight, right, y + rowHeight);
      doc.text(description, left + 3, y + 6);
      doc.text(formatNumber(line.quantity), 132, y + 6, { align: "right" });
      doc.text(money(line.unitPrice), 161, y + 6, { align: "right" });
      doc.text(money(line.totalExTax), right - 3, y + 6, { align: "right" });
      y += rowHeight;
    });

    const totalY = Math.min(Math.max(y + 10, 135), 176);
    doc.setFillColor(...pale);
    doc.roundedRect(120, totalY, 72, 31, 2, 2, "F");
    doc.setTextColor(...dark);
    doc.setFont("helvetica", "normal");
    doc.setFontSize(8);
    doc.text("Total HT", 124, totalY + 7);
    doc.text(money(invoice.totalExTax || invoice.totalIncTax || 0), 188, totalY + 7, { align: "right" });
    doc.text("TVA", 124, totalY + 15);
    doc.text(money(invoice.totalVat || 0), 188, totalY + 15, { align: "right" });
    doc.setFont("helvetica", "bold");
    doc.setFontSize(9);
    doc.text("Total TTC / Net à payer", 124, totalY + 24);
    doc.text(money(invoice.totalIncTax || 0), 188, totalY + 24, { align: "right" });
    if (issuer.paymentTerms) {
      doc.setTextColor(...muted);
      doc.setFont("helvetica", "normal");
      doc.setFontSize(8);
      doc.text(doc.splitTextToSize(String(issuer.paymentTerms), width), left, totalY + 55);
    }

    // Keep the payment area visually anchored to the bottom of the A4 page.
    const paymentY = 232;
    const hasCard = isEnabled(invoice.paypalEnabled ?? issuer.paypalEnabled) && invoice.paypalPaymentUrl;
    const bankWidth = hasCard ? 112 : width;
    drawPDFPaymentBox(doc, left, paymentY, bankWidth, "Paiement par virement bancaire", [
      `Référence : ${invoice.number || ""}`,
      issuer.iban ? `IBAN : ${issuer.iban}` : "",
      issuer.bic ? `BIC : ${issuer.bic}` : "",
    ]);
    if (hasCard) {
      const cardX = left + bankWidth + 4;
      const cardWidth = right - cardX;
      doc.setFillColor(...pale);
      doc.setDrawColor(170, 148, 223);
      doc.roundedRect(cardX, paymentY, cardWidth, 24, 2, 2, "FD");
      doc.setTextColor(41, 30, 73);
      doc.setFont("helvetica", "bold");
      doc.setFontSize(9);
      doc.text("Paiement par carte bancaire", cardX + 4, paymentY + 7, { maxWidth: cardWidth - 8 });
      doc.setFillColor(0, 112, 186);
      doc.roundedRect(cardX + 4, paymentY + 10, cardWidth - 8, 10, 2, 2, "F");
      doc.setTextColor(255, 255, 255);
      doc.text("Payer par carte", cardX + cardWidth / 2, paymentY + 16.5, { align: "center" });
      doc.link(cardX + 4, paymentY + 10, cardWidth - 8, 10, { url: invoice.paypalPaymentUrl });
    }

    doc.setTextColor(...muted);
    doc.setFont("helvetica", "normal");
    doc.setFontSize(7);
    const legal = legalMentions(invoice).join("\n");
    doc.text(doc.splitTextToSize(legal, width), left, 264);
    const filename = `${String(invoice.number || "facture").replace(/[^a-z0-9_-]+/gi, "-")}.pdf`;
    return { doc, filename };
  }

  function drawPDFParty(doc, x, y, width, title, values) {
    doc.setDrawColor(217, 224, 234);
    doc.roundedRect(x, y, width, 39, 2, 2, "S");
    doc.setTextColor(139, 111, 209);
    doc.setFont("helvetica", "bold");
    doc.setFontSize(7);
    doc.text(title, x + 4, y + 6);
    doc.setTextColor(35, 48, 68);
    doc.setFontSize(8);
    const lines = values.filter(Boolean).map(String);
    if (lines.length) {
      doc.setFont("helvetica", "bold");
      doc.text(doc.splitTextToSize(lines[0], width - 8), x + 4, y + 12);
      doc.setFont("helvetica", "normal");
      doc.text(doc.splitTextToSize(lines.slice(1).join("\n"), width - 8), x + 4, y + 16);
    }
  }

  function drawPDFBrandTitle(doc, text, x, y, color) {
    const scale = 4;
    const fontSize = 24;
    const canvas = document.createElement("canvas");
    const context = canvas.getContext("2d");
    context.font = `italic 900 ${fontSize * scale}px system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif`;
    const measuredWidth = Math.ceil(context.measureText(text).width);
    canvas.width = measuredWidth + (4 * scale);
    canvas.height = 32 * scale;
    context.scale(scale, scale);
    context.font = `italic 900 ${fontSize}px system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif`;
    context.fillStyle = `rgb(${color.join(",")})`;
    context.textBaseline = "top";
    context.fillText(text, 0, 0);
    const widthMM = Math.min(80, canvas.width / scale * 0.264583);
    const heightMM = canvas.height / scale * 0.264583;
    doc.addImage(canvas.toDataURL("image/png"), "PNG", x, y, widthMM, heightMM);
  }

  function drawPDFPaymentBox(doc, x, y, width, title, values) {
    doc.setFillColor(243, 240, 252);
    doc.setDrawColor(170, 148, 223);
    doc.roundedRect(x, y, width, 24, 2, 2, "FD");
    doc.setTextColor(41, 30, 73);
    doc.setFont("helvetica", "bold");
    doc.setFontSize(9);
    doc.text(title, x + 4, y + 7);
    doc.setFont("helvetica", "normal");
    doc.setFontSize(7.5);
    doc.text(values.filter(Boolean).join("\n"), x + 4, y + 13);
  }

  function blobDataURL(blob) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result);
      reader.onerror = reject;
      reader.readAsDataURL(blob);
    });
  }

  function invoiceHTML(invoice) {
    const issuer = invoice.issuerSnapshot || {};
    const address = [issuer.address, issuer.addressExtra, [issuer.postalCode, issuer.city].filter(Boolean).join(" "), issuer.country].filter(Boolean).map(escapeHTML).join("<br>");
    const clientAddress = [invoice.clientAddress, [invoice.clientPostalCode, invoice.clientCity].filter(Boolean).join(" "), invoice.clientCountry].filter(Boolean).map(escapeHTML).join("<br>");
    const issuerIDs = [issuer.siret ? `SIRET : ${escapeHTML(issuer.siret)}` : "", issuer.siren ? `SIREN : ${escapeHTML(issuer.siren)}` : ""].filter(Boolean).join(" · ");
    const lines = (invoice.lines || []).map((line) => `<tr><td>${escapeHTML(line.description || "")}</td><td>${formatNumber(line.quantity)}</td><td>${money(line.unitPrice)}</td><td>${money(line.totalExTax)}</td></tr>`).join("");
    const paypalButton = isEnabled(invoice.paypalEnabled ?? invoice.issuerSnapshot?.paypalEnabled) && invoice.paypalPaymentUrl
      ? `<div class="card-payment"><strong class="card-payment-title">Paiement par carte bancaire</strong><a class="bank-payment-link" href="${escapeAttribute(invoice.paypalPaymentUrl)}" target="_blank" rel="noopener noreferrer">Payer par carte</a></div>`
      : "";
    const paymentRowClass = paypalButton ? "payment-row has-card" : "payment-row";
    const clientSirenLine = clientSiren(invoice) ? `<br>SIREN : ${escapeHTML(clientSiren(invoice))}` : "";
    const html = `<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>${escapeHTML(invoice.number || "Facture")}</title><style>
      @page{size:A4;margin:0}*{box-sizing:border-box}body{margin:0;color:#18212f;font-family:Inter,system-ui,-apple-system,"Segoe UI",sans-serif}.invoice{position:relative;width:210mm;min-height:296mm;padding:18mm}.brand{display:flex;align-items:center;justify-content:space-between;gap:18px;padding-bottom:13px;border-bottom:3px solid #c0aeee}.brand-identity{display:flex;align-items:center;gap:14px}.brand img{width:54px;height:54px}.brand h1{margin:0;font-size:23px;font-style:italic;font-weight:900;line-height:1.1}.brand p{margin:4px 0 0;color:#c0aeee;font-size:10px;font-weight:800}.brand-invoice-meta{text-align:right}.brand-invoice-meta strong{display:block;font-size:16px}.brand-invoice-meta span{display:block;margin-top:5px;color:#667085;font-size:10px}.parties{display:grid;grid-template-columns:1fr 1fr;gap:18px;margin:24px 0}.party{padding:15px;border:1px solid #d9e0ea;border-radius:8px;font-size:11px;line-height:1.55}.party h3{margin:0 0 8px;color:#8b6fd1;font-size:10px;text-transform:uppercase;letter-spacing:1px}.party strong{display:block;font-size:13px}.identity-second-line{display:block;min-height:17px;margin-top:0}table{width:100%;border-collapse:collapse;font-size:11px}th{padding:10px;background:#233044;color:#fff;text-align:right}th:first-child{text-align:left}td{padding:11px 9px;border-bottom:1px solid #e3e7ed;text-align:right}td:first-child{text-align:left}.total{display:flex;justify-content:flex-end;margin-top:20px}.total div{min-width:72mm;padding:14px;background:#f3f0fc;border-radius:8px;display:grid;grid-template-columns:1fr auto;gap:8px 18px;font-weight:900}.bank{position:absolute;right:18mm;bottom:42mm;left:18mm;padding:13px 15px;border:1px solid #aa94df;border-radius:8px;background:#f3f0fc;color:#40345f;font-size:10px;line-height:1.65}.bank-title{display:block;margin-bottom:5px;color:#291e49;font-size:12px}.payment-terms{margin-top:18px;color:#667085;font-size:10px}.legal{position:absolute;right:18mm;bottom:16mm;left:18mm;border-top:1px solid #d9e0ea;padding-top:10px;color:#667085;font-size:9px;line-height:1.55}@media print{.invoice{height:296mm;overflow:hidden}}
      body{background:#e9eef5}.preview-toolbar{position:sticky;top:0;z-index:2;display:flex;justify-content:center;padding:12px;background:#233044}.preview-toolbar button{min-height:42px;padding:0 18px;border:0;border-radius:8px;background:#c0aeee;color:#18212f;font:inherit;font-weight:900;cursor:pointer}.invoice{margin:18px auto;background:#fff;box-shadow:0 12px 40px rgba(24,33,47,.16)}@media print{body{background:#fff}.preview-toolbar{display:none}.invoice{margin:0;box-shadow:none}}
      .payment-row{position:absolute;right:18mm;bottom:42mm;left:18mm;display:grid;grid-template-columns:1fr;gap:10px;align-items:stretch}.payment-row.has-card{grid-template-columns:minmax(0,1fr) 58mm}.payment-row .bank{position:relative;right:auto;bottom:auto;left:auto;min-height:27mm;padding:13px 15px}.card-payment{display:flex;flex-direction:column;justify-content:space-between;min-height:27mm;padding:13px 15px;border:1px solid #aa94df;border-radius:8px;background:#f3f0fc;color:#40345f}.card-payment-title{color:#291e49;font-size:12px;line-height:1.35}.bank-payment-link{display:inline-flex;align-items:center;justify-content:center;min-height:11mm;padding:0 12px;border-radius:7px;background:#0070ba;color:#fff;text-align:center;text-decoration:none;font-size:11px;font-weight:900}@media print{.bank-payment-link{background:#0070ba!important;color:#fff!important;print-color-adjust:exact;-webkit-print-color-adjust:exact}}
      @media print{html,body{width:209mm!important;height:285mm!important;min-height:0!important;margin:0!important;background:#fff!important;overflow:hidden!important}.invoice{position:relative!important;display:block!important;width:209mm!important;min-height:0!important;height:285mm!important;margin:0!important;overflow:hidden!important;background:#fff!important;box-shadow:none!important;break-inside:avoid!important;break-after:avoid!important;page-break-inside:avoid!important;page-break-after:avoid!important}.preview-toolbar{display:none!important}}
    </style></head><body><div class="preview-toolbar"><button type="button" onclick="window.print()">Imprimer / Enregistrer en PDF</button></div><main class="invoice"><header class="brand"><div class="brand-identity"><img src="${window.location.origin}/assets/img/flechemoica-logo.png" alt=""><div><h1>${escapeHTML(issuer.tradeName || "FLÈCHE-MOI ÇA")}</h1><p>FACTURE</p></div></div><div class="brand-invoice-meta"><strong>${escapeHTML(invoice.number || "")}</strong><span>Émise le ${escapeHTML(formatDate(invoice.issueDate))}</span><span>Échéance le ${escapeHTML(formatDate(invoice.dueDate || invoice.issueDate))}</span></div></header><section class="parties"><div class="party"><h3>Émetteur</h3><strong>${escapeHTML(issuer.tradeName || "FLÈCHE-MOI ÇA")}</strong><span class="identity-second-line">${escapeHTML(issuer.legalName || "")} — ${escapeHTML(issuer.legalForm || "Entrepreneur individuel")}</span>${address}<br>${issuerIDs}${issuer.email ? `<br>${escapeHTML(issuer.email)}` : ""}</div><div class="party"><h3>Client</h3><strong>${escapeHTML(invoice.clientName || "")}</strong><span class="identity-second-line">${invoice.clientSecondaryLine ? escapeHTML(invoice.clientSecondaryLine) : "&nbsp;"}</span>${clientAddress}${clientSirenLine}${invoice.clientEmail ? `<br>${escapeHTML(invoice.clientEmail)}` : ""}</div></section><table><thead><tr><th>Description</th><th>Quantité</th><th>Prix unitaire HT</th><th>Total HT</th></tr></thead><tbody>${lines}</tbody></table><div class="total"><div><span>Total HT</span><strong>${money(invoice.totalExTax || invoice.totalIncTax || 0)}</strong><span>TVA</span><strong>${money(invoice.totalVat || 0)}</strong><span>Total TTC / Net à payer</span><strong>${money(invoice.totalIncTax || 0)}</strong></div></div>${issuer.paymentTerms ? `<div class="payment-terms">${escapeHTML(issuer.paymentTerms)}</div>` : ""}<div class="bank"><strong class="bank-title">Paiement par virement bancaire</strong><strong>Bénéficiaire :</strong> ${escapeHTML(issuer.legalName || "Nathan Piaget")}<br><strong>Référence :</strong> ${escapeHTML(invoice.number || "")}<br>${issuer.iban ? `<strong>IBAN :</strong> ${escapeHTML(issuer.iban)}<br>` : ""}${issuer.bic ? `<strong>BIC :</strong> ${escapeHTML(issuer.bic)}` : ""}</div><footer class="legal">${legalMentions(invoice).map(escapeHTML).join("<br>")}</footer></main></body></html>`;
    return html
      .replace(/<strong>Bénéficiaire :<\/strong>[^<]*<br>/, "")
      .replace('<div class="bank">', `<div class="${paymentRowClass}"><div class="bank">`)
      .replace('</div><footer class="legal">', `</div>${paypalButton}</div><footer class="legal">`)
      .replace('onclick="window.print()"', 'onclick="printInvoice()"')
      .replace('</body>', `<script>
        async function printInvoice() {
          const button = document.querySelector('.preview-toolbar button');
          if (button) button.disabled = true;
          try {
            if (document.fonts && document.fonts.ready) await document.fonts.ready;
            await Promise.all(Array.from(document.images).map((img) => img.complete ? Promise.resolve() : new Promise((resolve) => { img.onload = resolve; img.onerror = resolve; })));
            await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
            window.focus();
            window.print();
          } finally {
            if (button) button.disabled = false;
          }
        }
      <\/script></body>`);
  }

  function togglePanel(id) { node(id).classList.toggle("is-hidden"); }
  function node(id) { return document.getElementById(id); }
  function isEnabled(value) { return value === true || value === "true" || value === "on" || value === 1; }
  function round(value) { return Math.round((Number(value) + Number.EPSILON) * 100) / 100; }
  function isoDate(date) {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, "0");
    const day = String(date.getDate()).padStart(2, "0");
    return `${year}-${month}-${day}`;
  }

  function addDaysToISODate(value, days) {
    const date = new Date(`${value}T12:00:00`);
    if (Number.isNaN(date.getTime())) return value;
    date.setDate(date.getDate() + days);
    return isoDate(date);
  }
  function formatDate(value) { return value ? new Intl.DateTimeFormat("fr-FR").format(new Date(`${value}T12:00:00`)) : ""; }
  function firestoreDate(value) { return value?.toDate ? value.toDate() : value instanceof Date ? value : value ? new Date(value) : null; }
  function formatDateTime(value) { return new Intl.DateTimeFormat("fr-FR", { dateStyle: "short", timeStyle: "short" }).format(value); }
  function money(value) { return new Intl.NumberFormat("fr-FR", { style: "currency", currency: "EUR" }).format(Number(value || 0)); }
  function formatNumber(value) { return new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 2 }).format(Number(value || 0)); }
  function escapeHTML(value) { const div = document.createElement("div"); div.textContent = String(value ?? ""); return div.innerHTML; }
  function escapeAttribute(value) { return escapeHTML(value).replace(/"/g, "&quot;"); }
  function setStatus(message, kind = "") { const status = node("invoicing-status"); if (!status) return; status.textContent = message; status.dataset.kind = kind; }

  return { init, start, stop, createInvoicePDFFile };
})();
