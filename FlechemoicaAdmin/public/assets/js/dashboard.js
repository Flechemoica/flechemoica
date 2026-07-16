const DashboardView = (() => {
  const loginView = document.getElementById("login-view");
  const dashboardView = document.getElementById("dashboard-view");
  const accountEmail = document.getElementById("account-email");
  const logoutButton = document.getElementById("logout-button");
  const homeButton = document.getElementById("dashboard-home-button");
  const navItems = Array.from(document.querySelectorAll("[data-panel-target]"));
  const workspacePanels = Array.from(document.querySelectorAll(".workspace-panel"));
  const panelRoutes = {
    "overview-panel": "/",
    "users-panel": "/user.html",
    "grids-panel": "/grille.html",
    "accounting-panel": "/comptabilite.html",
  };
  const routePanels = Object.fromEntries(
    Object.entries(panelRoutes).map(([panelID, path]) => [path, panelID])
  );

  function showPanel(panelID, options = {}) {
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
  }

  function showDashboard(user) {
    accountEmail.textContent = user.email || "";
    loginView.classList.add("is-hidden");
    dashboardView.classList.remove("is-hidden");
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

  function getPanelFromPath() {
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
    if (window.location.pathname === path) return;
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
