const DashboardView = (() => {
  const loginView = document.getElementById("login-view");
  const dashboardView = document.getElementById("dashboard-view");
  const accountEmail = document.getElementById("account-email");
  const logoutButton = document.getElementById("logout-button");
  const homeButton = document.getElementById("dashboard-home-button");
  const navItems = Array.from(document.querySelectorAll("[data-panel-target]"));
  const workspacePanels = Array.from(document.querySelectorAll(".workspace-panel"));
  let currentProfile = null;
  const panelRoutes = {
    "overview-panel": "/",
    "users-panel": "/user.html",
    "grids-panel": "/grille.html",
    "notifications-panel": "/notifications.html",
    "communications-panel": "/?panel=communications",
    "social-networks-panel": "/reseaux-sociaux.html",
    "invoicing-panel": "/facturation.html",
    "accounting-panel": "/comptabilite.html",
  };
  const routePanels = Object.fromEntries(
    Object.entries(panelRoutes).map(([panelID, path]) => [path, panelID])
  );

  function showPanel(panelID, options = {}) {
    if (panelID === "accounting-panel" && !canAccessAccounting()) {
      panelID = "overview-panel";
      options = { ...options, push: false };
      if (window.location.pathname === "/comptabilite.html") {
        window.history.replaceState({ panelID }, "", "/");
      }
    }

    navItems.forEach((item) => {
      item.classList.toggle("is-active", item.dataset.panelTarget === panelID);
    });

    workspacePanels.forEach((panel) => {
      panel.classList.toggle("is-hidden", panel.id !== panelID);
    });

    if (panelID === "users-panel") {
      UsersView.start();
    } else if (panelID === "user-detail-panel") {
      UsersView.startDetail(getUserIDFromPath());
    } else {
      UsersView.stop();
    }

    if (panelID === "grids-panel") {
      GridsView.start();
    } else if (panelID === "grid-detail-panel") {
      GridsView.startDetail(getGridIDFromPath());
    } else {
      GridsView.stop();
    }

    if (panelID === "notifications-panel") {
      NotificationsView.start();
    } else {
      NotificationsView.stop();
    }

    if (panelID === "communications-panel") {
      CommunicationsView.start();
    } else {
      CommunicationsView.stop();
    }

    if (panelID === "social-networks-panel") {
      SocialNetworksView.start();
    } else {
      SocialNetworksView.stop();
    }

    if (panelID === "accounting-panel") {
      AccountingView.start();
    } else {
      AccountingView.stop();
    }

    if (panelID === "invoicing-panel") {
      InvoicingView.start();
    } else {
      InvoicingView.stop();
    }

    if (panelID === "overview-panel") TasksView.start();
    else TasksView.stop();

    if (options.push !== false) {
      pushRoute(panelID);
    }
  }

  function showLogin() {
    loginView.classList.remove("is-hidden");
    dashboardView.classList.add("is-hidden");
    accountEmail.textContent = "";
    UsersView.stop();
    GridsView.stop();
    NotificationsView.stop();
    CommunicationsView.stop();
    SocialNetworksView.stop();
    AccountingView.stop();
    InvoicingView.stop();
    TasksView.stop();
  }

  function showDashboard(user, profile) {
    currentProfile = profile || null;
    accountEmail.textContent = user.email || "";
    loginView.classList.add("is-hidden");
    dashboardView.classList.remove("is-hidden");
    applyAccessControls();
    showPanel(getPanelFromPath(), { push: false });
  }

  function showUserDetail(userID) {
    showPanel("user-detail-panel", { push: false });
  }

  function showGridDetail(gridID) {
    showPanel("grid-detail-panel", { push: false });
  }

  function init() {
    UsersView.init();
    GridsView.init();
    NotificationsView.init();
    CommunicationsView.init();
    SocialNetworksView.init();
    AccountingView.init();
    InvoicingView.init();
    TasksView.init();

    navItems.forEach((item) => {
      item.addEventListener("click", () => {
        showPanel(item.dataset.panelTarget);
      });
    });

    logoutButton.addEventListener("click", () => {
      AuthGate.signOut();
    });

    homeButton.addEventListener("click", () => {
      showPanel("overview-panel");
    });

    window.addEventListener("popstate", () => {
      if (!dashboardView.classList.contains("is-hidden")) {
        showPanel(getPanelFromPath(), { push: false });
      }
    });
  }

  function canAccessAccounting() {
    return AuthGate.hasAccountingAccess(currentProfile);
  }

  function applyAccessControls() {
    const accountingNav = document.querySelector("[data-panel-target='accounting-panel']");
    if (accountingNav) {
      const canAccess = canAccessAccounting();
      accountingNav.hidden = !canAccess;
      accountingNav.setAttribute("aria-hidden", String(!canAccess));
      accountingNav.classList.toggle("is-hidden", !canAccess);
      if (!canAccess) accountingNav.classList.remove("is-active");
    }
  }

  function getPanelFromPath() {
    const requestedPanel = new URLSearchParams(window.location.search).get("panel");
    if (requestedPanel === "notifications") {
      return "notifications-panel";
    }

    if (requestedPanel === "communications") {
      return "communications-panel";
    }

    if (/^\/user\/[^/]+\.html$/.test(window.location.pathname)) {
      return "user-detail-panel";
    }

    if (/^\/grille\/[^/]+\.html$/.test(window.location.pathname)) {
      return "grid-detail-panel";
    }

    return routePanels[window.location.pathname] || "overview-panel";
  }

  function pushRoute(panelID) {
    const path = panelRoutes[panelID] || "/";
    const currentPath = `${window.location.pathname}${window.location.search}`;
    if (currentPath === path) return;
    window.history.pushState({ panelID }, "", path);
  }

  function getUserIDFromPath() {
    const match = window.location.pathname.match(/^\/user\/([^/]+)\.html$/);
    return match ? decodeURIComponent(match[1]) : "";
  }

  function getGridIDFromPath() {
    const match = window.location.pathname.match(/^\/grille\/([^/]+)\.html$/);
    return match ? decodeURIComponent(match[1]) : "";
  }

  return {
    init,
    showDashboard,
    showGridDetail,
    showUserDetail,
    showLogin,
  };
})();
