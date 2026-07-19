(() => {
  const API_URL = "https://europe-west1-flechemoica.cloudfunctions.net/paypalInvoicePayment";
  const token = new URLSearchParams(window.location.search).get("token") || "";
  const loadingPanel = document.getElementById("loading-panel");
  const layout = document.getElementById("payment-layout");
  const panel = document.getElementById("payment-panel");
  const status = document.getElementById("payment-status");
  const button = document.getElementById("payment-button");

  function endpoint(action) {
    return `${API_URL}?token=${encodeURIComponent(token)}&action=${encodeURIComponent(action)}`;
  }

  function showFatal(message) {
    loadingPanel.innerHTML = `<strong>Paiement indisponible</strong><p>${escapeHTML(message)}</p>`;
  }

  function escapeHTML(value) {
    const element = document.createElement("div");
    element.textContent = String(value || "");
    return element.innerHTML;
  }

  function loadPayPalSDK(clientID, currency) {
    return new Promise((resolve, reject) => {
      const script = document.createElement("script");
      script.src = `https://www.paypal.com/sdk/js?client-id=${encodeURIComponent(clientID)}&components=card-fields&currency=${encodeURIComponent(currency)}`;
      script.onload = resolve;
      script.onerror = () => reject(new Error("Le module de paiement PayPal ne peut pas être chargé."));
      document.head.appendChild(script);
    });
  }

  async function start() {
    if (!token) throw new Error("Le lien de paiement est incomplet.");
    const detailsResponse = await fetch(endpoint("details"), { headers: { Accept: "application/json" } });
    const details = await detailsResponse.json().catch(() => ({}));
    if (!detailsResponse.ok || !details.clientID || !details.invoice) throw new Error(details.message || "Cette facture n’est pas disponible.");
    const invoice = details.invoice;
    const formattedAmount = new Intl.NumberFormat("fr-FR", { style: "currency", currency: invoice.currency }).format(Number(invoice.amount));

    document.getElementById("client-email").value = invoice.clientEmail;
    document.getElementById("invoice-number").textContent = invoice.number;
    document.getElementById("invoice-client").textContent = invoice.clientName;
    document.getElementById("invoice-address").textContent = [invoice.clientAddress, invoice.clientPostalCode, invoice.clientCity].filter(Boolean).join(" ");
    document.getElementById("invoice-email").textContent = invoice.clientEmail;
    document.getElementById("invoice-total").textContent = formattedAmount;
    button.textContent = `Payer ${formattedAmount}`;

    await loadPayPalSDK(details.clientID, invoice.currency);
    if (!window.paypal?.CardFields) throw new Error("Le paiement direct par carte n’est pas disponible.");

    const fields = window.paypal.CardFields({
      createOrder: async () => {
        status.textContent = "";
        const response = await fetch(endpoint("create"), { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" });
        const payload = await response.json().catch(() => ({}));
        if (!response.ok || !payload.id) throw new Error(payload.message || "Impossible de préparer le paiement.");
        return payload.id;
      },
      onApprove: async (data) => {
        button.disabled = true;
        button.textContent = "Confirmation…";
        const response = await fetch(endpoint("capture"), { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ orderID: data.orderID }) });
        const payload = await response.json().catch(() => ({}));
        if (!response.ok || payload.status !== "COMPLETED") throw new Error(payload.message || "Le paiement n’a pas pu être confirmé.");
        panel.innerHTML = '<div class="payment-success"><h1>Paiement confirmé</h1><p>Merci, le règlement de votre facture a bien été enregistré.</p></div>';
      },
      onError: (error) => {
        button.disabled = false;
        button.textContent = `Payer ${formattedAmount}`;
        status.textContent = error?.message || "Le paiement a échoué. Vérifiez les informations puis réessayez.";
      },
      style: {
        input: {
          appearance: "none",
          "font-size": "16px",
          "font-family": "Inter, Arial, sans-serif",
          height: "46px",
          padding: "0 13px",
          color: "#18212f",
          "background-color": "#ffffff",
          "box-sizing": "border-box",
          border: "0",
          outline: "0",
        },
      },
    });

    if (!fields.isEligible()) throw new Error("Le paiement direct par carte n’est pas disponible pour cette transaction.");
    loadingPanel.classList.add("is-hidden");
    layout.classList.remove("is-hidden");
    await Promise.all([
      fields.NameField({ placeholder: "Prénom et nom" }).render("#card-name"),
      fields.NumberField({ placeholder: "Numéro de carte" }).render("#card-number"),
      fields.ExpiryField({ placeholder: "MM/AA" }).render("#card-expiry"),
      fields.CVVField({ placeholder: "CVV" }).render("#card-cvv"),
    ]);

    button.disabled = false;
    button.addEventListener("click", async () => {
      button.disabled = true;
      button.textContent = "Paiement en cours…";
      status.textContent = "";
      try {
        await fields.submit({
          billingAddress: {
            addressLine1: String(invoice.clientAddress || "").trim(),
            adminArea2: String(invoice.clientCity || "").trim(),
            postalCode: String(invoice.clientPostalCode || "").trim(),
            countryCode: invoice.clientCountryCode,
          },
        });
      } catch (error) {
        button.disabled = false;
        button.textContent = `Payer ${formattedAmount}`;
        status.textContent = error?.message || "Vérifiez les informations de paiement.";
      }
    });
  }

  start().catch((error) => showFatal(error.message));
})();
