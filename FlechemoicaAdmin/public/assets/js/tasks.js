const TasksView = (() => {
  const form = document.getElementById("task-form");
  const titleInput = document.getElementById("task-title");
  const categoryInput = document.getElementById("task-category");
  const dueDateInput = document.getElementById("task-due-date");
  const list = document.getElementById("task-list");
  const count = document.getElementById("tasks-count");
  const message = document.getElementById("task-message");
  let unsubscribe = null;
  let firestore = null;

  const categories = [
    { value: "administratif", label: "Administratif" },
    { value: "dev-console", label: "DEV console" },
    { value: "dev-site", label: "DEV site" },
    { value: "dev-ios", label: "DEV iOS" },
    { value: "publicites", label: "Publicités" },
    { value: "reseaux-sociaux", label: "Réseaux Sociaux" },
    { value: "comptabilite", label: "Comptabilité" },
    { value: "autres", label: "Autres" },
  ];

  function init() {
    form?.addEventListener("submit", addTask);
    list?.addEventListener("change", handleTaskChange);
    list?.addEventListener("click", deleteTask);
    window.addEventListener("resize", updateListViewport);
  }

  function start() {
    if (unsubscribe || !form) return;
    try {
      firestore = AuthGate.ensureFirebase().firestore;
      if (!firestore) throw new Error("Base de données indisponible.");
      subscribe();
    } catch (error) {
      setMessage(error.message || "Impossible de charger les tâches.", true);
    }
  }

  function subscribe() {
    if (unsubscribe) unsubscribe();
    unsubscribe = null;
    list.replaceChildren();
    count.textContent = "";
    setMessage("Chargement…");
    try {
      unsubscribe = tasksCollection().orderBy("createdAt", "desc").onSnapshot(
        renderTasks,
        (error) => {
          console.error("Chargement des tâches impossible:", error);
          setMessage("Impossible de charger les tâches.", true);
        }
      );
    } catch (error) {
      setMessage(error.message || "Impossible de charger les tâches.", true);
    }
  }

  function stop() {
    if (unsubscribe) unsubscribe();
    unsubscribe = null;
  }

  async function addTask(event) {
    event.preventDefault();
    const title = titleInput.value.trim();
    if (!title || !firestore) return;
    const button = form.querySelector("button[type='submit']");
    button.disabled = true;
    try {
      await tasksCollection().add({
        title,
        category: normalizedCategory(categoryInput?.value),
        dueDate: dueDateInput.value || null,
        completed: false,
        scope: "team",
        createdBy: firebase.auth().currentUser?.uid || null,
        createdAt: firebase.firestore.FieldValue.serverTimestamp(),
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      });
      form.reset();
      if (categoryInput) categoryInput.value = "autres";
      titleInput.focus();
      setMessage("");
    } catch (error) {
      setMessage("La tâche n’a pas pu être ajoutée.", true);
    } finally {
      button.disabled = false;
    }
  }

  async function toggleTask(event) {
    const checkbox = event.target.closest("input[data-task-id]");
    if (!checkbox || !firestore) return;
    checkbox.disabled = true;
    try {
      await tasksCollection().doc(checkbox.dataset.taskId).update({
        completed: checkbox.checked,
        completedAt: checkbox.checked ? firebase.firestore.FieldValue.serverTimestamp() : null,
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      });
    } catch (error) {
      checkbox.checked = !checkbox.checked;
      checkbox.disabled = false;
      setMessage("La tâche n’a pas pu être modifiée.", true);
    }
  }

  function handleTaskChange(event) {
    if (event.target.matches("select[data-task-category-id]")) {
      updateTaskCategory(event);
      return;
    }
    toggleTask(event);
  }

  async function updateTaskCategory(event) {
    const select = event.target;
    if (!firestore) return;
    const previousCategory = select.dataset.previousCategory || "autres";
    const category = normalizedCategory(select.value);
    select.disabled = true;
    try {
      await tasksCollection().doc(select.dataset.taskCategoryId).update({
        category,
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      });
      select.dataset.previousCategory = category;
    } catch (error) {
      select.value = previousCategory;
      applyCategoryClass(select, previousCategory);
      select.disabled = false;
      setMessage("La catégorie n’a pas pu être modifiée.", true);
    }
  }

  async function deleteTask(event) {
    const button = event.target.closest("button[data-delete-task]");
    if (!button || !firestore) return;
    button.disabled = true;
    try {
      await tasksCollection().doc(button.dataset.deleteTask).delete();
    } catch (error) {
      button.disabled = false;
      setMessage("La tâche n’a pas pu être supprimée.", true);
    }
  }

  function renderTasks(snapshot) {
    const tasks = snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    tasks.sort((a, b) => Number(a.completed) - Number(b.completed));
    const remaining = tasks.filter((task) => !task.completed).length;
    count.textContent = remaining ? `${remaining} à faire` : "";
    setMessage(tasks.length ? "" : "Aucune tâche pour le moment.");
    list.replaceChildren(...tasks.map(renderTask));
    requestAnimationFrame(updateListViewport);
  }

  function updateListViewport() {
    const items = Array.from(list?.children || []);
    const shouldScroll = items.length > 5;
    list?.classList.toggle("is-scrollable", shouldScroll);
    if (!list) return;
    if (!shouldScroll) {
      list.style.removeProperty("max-height");
      return;
    }
    const gap = Number.parseFloat(getComputedStyle(list).rowGap) || 0;
    const visibleHeight = items
      .slice(0, 5)
      .reduce((height, item) => height + item.getBoundingClientRect().height, gap * 4);
    list.style.maxHeight = `${Math.ceil(visibleHeight)}px`;
  }

  function renderTask(task) {
    const item = document.createElement("li");
    item.className = `task-item${task.completed ? " is-completed" : ""}`;
    const checkbox = document.createElement("input");
    checkbox.type = "checkbox";
    checkbox.checked = Boolean(task.completed);
    checkbox.dataset.taskId = task.id;
    checkbox.setAttribute("aria-label", `Modifier l’état de « ${task.title} »`);
    const copy = document.createElement("span");
    copy.className = "task-copy";
    const title = document.createElement("strong");
    title.textContent = task.title || "Tâche sans titre";
    copy.appendChild(title);
    const metadata = document.createElement("span");
    metadata.className = "task-metadata";
    const category = normalizedCategory(task.category);
    const categorySelect = document.createElement("select");
    categorySelect.className = "task-category-tag";
    categorySelect.dataset.taskCategoryId = task.id;
    categorySelect.dataset.previousCategory = category;
    categorySelect.setAttribute("aria-label", `Catégorie de « ${task.title} »`);
    categories.forEach(({ value, label }) => {
      const option = document.createElement("option");
      option.value = value;
      option.textContent = label;
      categorySelect.appendChild(option);
    });
    categorySelect.value = category;
    applyCategoryClass(categorySelect, category);
    categorySelect.addEventListener("change", () => applyCategoryClass(categorySelect, categorySelect.value));
    metadata.appendChild(categorySelect);
    if (task.dueDate) {
      const due = document.createElement("small");
      due.textContent = formatDueDate(task.dueDate);
      if (!task.completed && task.dueDate < localISODate()) due.className = "is-overdue";
      metadata.appendChild(due);
    }
    copy.appendChild(metadata);
    const remove = document.createElement("button");
    remove.type = "button";
    remove.className = "task-delete-button";
    remove.dataset.deleteTask = task.id;
    remove.setAttribute("aria-label", `Supprimer « ${task.title} »`);
    remove.textContent = "×";
    item.append(checkbox, copy, remove);
    return item;
  }

  function normalizedCategory(value) {
    return categories.some((category) => category.value === value) ? value : "autres";
  }

  function applyCategoryClass(element, value) {
    categories.forEach((category) => element.classList.remove(`category-${category.value}`));
    element.classList.add(`category-${normalizedCategory(value)}`);
  }

  function formatDueDate(value) {
    const date = new Date(`${value}T12:00:00`);
    const formatted = new Intl.DateTimeFormat("fr-FR", { day: "numeric", month: "short", year: "numeric" }).format(date);
    return `Échéance : ${formatted}`;
  }

  function localISODate() {
    const now = new Date();
    return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
  }

  function setMessage(text, isError = false) {
    message.textContent = text;
    message.classList.toggle("is-error", isError);
  }

  function tasksCollection() {
    if (!firebase.auth().currentUser) throw new Error("Utilisateur non connecté.");
    return firestore.collection("adminTasks");
  }

  return { init, start, stop };
})();
