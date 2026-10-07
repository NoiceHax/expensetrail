import "./styles.css";

const $ = (id) => document.getElementById(id);
const money = (n) => "₹" + Number(n).toLocaleString("en-IN", { maximumFractionDigits: 2 });

async function api(path, options) {
  const res = await fetch(path, { headers: { "Content-Type": "application/json" }, ...options });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(typeof body.detail === "string" ? body.detail : "Request failed (" + res.status + ")");
  }
  return res.status === 204 ? null : res.json();
}

function renderSummary(s) {
  const top = s.by_category[0];
  $("summary").innerHTML = `
    <div class="card"><span>Total spent</span><strong>${money(s.total)}</strong></div>
    <div class="card"><span>Expenses</span><strong>${s.count}</strong></div>
    <div class="card"><span>Top category</span><strong>${top ? top.category : "-"}</strong></div>`;
  const select = $("filter");
  const current = select.value;
  select.innerHTML = '<option value="">All categories</option>' +
    s.by_category.map((c) => `<option value="${c.category}">${c.category} (${c.count})</option>`).join("");
  select.value = current;
}

function renderList(items) {
  $("empty").style.display = items.length ? "none" : "block";
  $("list").innerHTML = items.map((e) => `
    <li>
      <div><strong></strong><small>${e.category} · ${e.spent_on}</small></div>
      <div class="amt">${money(e.amount)}</div>
      <button class="del" data-id="${e.id}" aria-label="Delete expense">×</button>
    </li>`).join("");
  // set titles via textContent so user input is never interpreted as HTML
  [...$("list").children].forEach((li, i) => { li.querySelector("strong").textContent = items[i].title; });
}

async function refresh() {
  const category = $("filter").value;
  const [summary, items] = await Promise.all([
    api("/api/summary"),
    api("/api/expenses" + (category ? "?category=" + encodeURIComponent(category) : "")),
  ]);
  renderSummary(summary);
  renderList(items);
}

$("form").addEventListener("submit", async (event) => {
  event.preventDefault();
  $("error").textContent = "";
  const data = Object.fromEntries(new FormData(event.target));
  data.amount = Number(data.amount);
  if (!data.spent_on) delete data.spent_on;
  try {
    await api("/api/expenses", { method: "POST", body: JSON.stringify(data) });
    event.target.reset();
    await refresh();
  } catch (err) {
    $("error").textContent = err.message;
  }
});

$("list").addEventListener("click", async (event) => {
  const id = event.target.dataset.id;
  if (!id) return;
  await api("/api/expenses/" + id, { method: "DELETE" });
  await refresh();
});

$("filter").addEventListener("change", refresh);
refresh().catch((err) => { $("error").textContent = err.message; });
