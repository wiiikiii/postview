import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "title", "viewPanel", "viewBody", "editForm", "editFields", "pkInputs"]
  static values  = { database: String, table: String }

  #colTypes = {}
  #mode     = "view"   // "view" | "edit" | "new"
  #tip      = null

  connect() {
    this.#colTypes = JSON.parse(this.element.dataset.colTypes || "{}")
    this.#tip = document.createElement("div")
    this.#tip.className =
      "fixed z-[9999] hidden max-w-sm rounded-xl border border-gray-700 " +
      "bg-gray-900 text-white text-xs px-3 py-2 shadow-2xl font-mono " +
      "whitespace-pre-wrap break-all pointer-events-none"
    document.body.appendChild(this.#tip)
  }

  disconnect() {
    this.#tip?.remove()
    this.#tip = null
  }

  // ── open existing row ───────────────────────────────────────────────────

  open(event) {
    const tr  = event.currentTarget
    const row = JSON.parse(tr.dataset.row)
    const pk  = JSON.parse(tr.dataset.pk)
    this.#fillExisting(row, pk)
    this.dialogTarget.showModal()
  }

  // ── open new-record form ────────────────────────────────────────────────

  openNew(event) {
    event.stopPropagation()
    this.#fillNew()
    this.dialogTarget.showModal()
  }

  // ── dialog controls ─────────────────────────────────────────────────────

  close() {
    this.dialogTarget.close()
  }

  backdropClose(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  stopEvent(event) {
    event.stopPropagation()
  }

  showTooltip(event) {
    const text = event.currentTarget.dataset.tooltip
    if (!text || !this.#tip) return
    this.#tip.textContent = text
    this.#tip.classList.remove("hidden")
    this.#place(event.currentTarget)
  }

  hideTooltip() {
    this.#tip?.classList.add("hidden")
  }

  #place(el) {
    const r   = el.getBoundingClientRect()
    const tip = this.#tip
    const gap = 8
    const vw  = window.innerWidth
    const vh  = window.innerHeight

    // Measure after making visible (hidden → measure → position)
    tip.style.left = "-9999px"
    tip.style.top  = "-9999px"
    const tw = tip.offsetWidth
    const th = tip.offsetHeight

    let left = Math.min(r.left, vw - tw - gap)
    if (left < gap) left = gap

    const below = r.bottom + gap + th < vh
    const top   = below ? r.bottom + gap : r.top - th - gap

    tip.style.left = `${left}px`
    tip.style.top  = `${top}px`
  }

  edit() {
    this.#mode = "edit"
    this.viewPanelTarget.classList.add("hidden")
    this.editFormTarget.classList.remove("hidden")
    this.editFormTarget.querySelector("input:not([type=hidden]),textarea")?.focus()
  }

  cancelEdit() {
    if (this.#mode === "new") {
      this.close()
      return
    }
    this.#mode = "view"
    this.editFormTarget.classList.add("hidden")
    this.viewPanelTarget.classList.remove("hidden")
  }

  // ── private ─────────────────────────────────────────────────────────────

  #fillExisting(row, pk) {
    this.#mode = "view"
    const pkCols = Object.keys(pk)

    this.titleTarget.textContent = pkCols.map(k => `${k} = ${pk[k]}`).join(" · ")

    // View body
    this.viewBodyTarget.innerHTML = Object.entries(row).map(([col, val]) => {
      const isNull = val === null
      const display = isNull
        ? `<span class="italic text-gray-300">NULL</span>`
        : `<span class="break-all">${esc(String(val))}</span>`
      return `<div class="flex gap-4 py-2.5 border-b border-gray-100 last:border-0">
        <dt class="w-2/5 shrink-0 text-xs font-medium text-gray-400 pt-0.5">${esc(col)}</dt>
        <dd class="flex-1 font-mono text-xs text-gray-800 min-w-0">${display}</dd>
      </div>`
    }).join("")

    // PK hidden inputs
    this.pkInputsTarget.innerHTML = pkCols
      .map(k => `<input type="hidden" name="pk[${esc(k)}]" value="${attr(String(pk[k]))}">`)
      .join("")

    // Edit fields
    this.editFieldsTarget.innerHTML = Object.entries(row)
      .map(([col, val]) => this.#renderField(col, val, pkCols.includes(col)))
      .join("")
    this.#wireNullToggles()

    this.editFormTarget.querySelector('[name="_method"]').value = "patch"
    this.editFormTarget.action =
      `/databases/${this.databaseValue}/${encodeURIComponent(this.tableValue)}/rows`

    this.viewPanelTarget.classList.remove("hidden")
    this.editFormTarget.classList.add("hidden")
  }

  #fillNew() {
    this.#mode = "new"
    this.titleTarget.textContent = "Neuer Eintrag"

    this.pkInputsTarget.innerHTML = ""
    this.editFieldsTarget.innerHTML = Object.keys(this.#colTypes)
      .map(col => this.#renderField(col, null, false, true))
      .join("")
    this.#wireNullToggles()

    this.editFormTarget.querySelector('[name="_method"]').value = "post"
    this.editFormTarget.action =
      `/databases/${this.databaseValue}/${encodeURIComponent(this.tableValue)}/rows`

    this.viewPanelTarget.classList.add("hidden")
    this.editFormTarget.classList.remove("hidden")
    this.editFormTarget.querySelector("input:not([type=hidden]),textarea")?.focus()
  }

  // col, val: current value (null for new), isPk, isNew
  #renderField(col, val, isPk, isNew = false) {
    const type   = this.#colTypes[col] || ""
    const isNull = val === null
    const valStr = isNull ? "" : String(val)

    if (isPk && !isNew) {
      return `<div class="flex gap-4 py-2.5 border-b border-gray-100 last:border-0 items-start">
        <span class="w-2/5 shrink-0 text-xs font-medium text-gray-400 pt-1">
          ${esc(col)} <span class="text-amber-500 font-semibold">PK</span>
        </span>
        <span class="flex-1 font-mono text-xs text-gray-400 pt-1 break-all">
          ${isNull ? "NULL" : esc(valStr)}
        </span>
      </div>`
    }

    const name = `row[${esc(col)}]`
    const pkBadge = isPk
      ? ` <span class="ml-1 text-amber-500 font-semibold">PK</span>`
      : ""

    if (/^bool/i.test(type)) {
      const checked = (!isNull && (val === true || val === "t" || val === "1")) ? "checked" : ""
      return `<div class="flex gap-4 py-2.5 border-b border-gray-100 last:border-0 items-center">
        <label class="w-2/5 shrink-0 text-xs font-medium text-gray-400">
          ${esc(col)}${pkBadge}
        </label>
        <input type="checkbox" name="${name}" value="t" ${checked}
               class="h-4 w-4 accent-sky-500 rounded">
      </div>`
    }

    const isLong    = !isNull && valStr.length > 80
    const nullClass = isNull
      ? "w-full font-mono text-xs rounded-lg border border-gray-200 px-2.5 py-1.5 focus:outline-none focus:ring-1 focus:ring-sky-400 bg-gray-50 text-gray-400 italic"
      : "w-full font-mono text-xs rounded-lg border border-gray-200 px-2.5 py-1.5 focus:outline-none focus:ring-1 focus:ring-sky-400"

    const placeholder = isNull ? "NULL" : ""

    const inputEl = isLong
      ? `<textarea name="${name}" rows="3"
           data-field-input="${esc(col)}"
           class="${nullClass} resize-y"
           placeholder="${placeholder}">${esc(valStr)}</textarea>`
      : `<input type="text" name="${name}" value="${attr(valStr)}"
           data-field-input="${esc(col)}"
           class="${nullClass}"
           placeholder="${placeholder}">`

    const nullChecked = isNull ? "checked" : ""
    return `<div class="flex gap-4 py-2.5 border-b border-gray-100 last:border-0 items-start">
      <label class="w-2/5 shrink-0 text-xs font-medium text-gray-400 pt-1.5">
        ${esc(col)}${pkBadge}
      </label>
      <div class="flex-1 min-w-0 space-y-1.5">
        ${inputEl}
        <label class="flex items-center gap-1.5 cursor-pointer select-none">
          <input type="checkbox" name="null_cols[]" value="${esc(col)}" ${nullChecked}
                 data-null-toggle="${esc(col)}"
                 class="h-3 w-3 rounded accent-sky-500">
          <span class="text-xs text-gray-400">NULL</span>
        </label>
      </div>
    </div>`
  }

  #wireNullToggles() {
    this.editFieldsTarget.querySelectorAll("[data-null-toggle]").forEach(cb => {
      const input = this.editFieldsTarget.querySelector(`[data-field-input="${CSS.escape(cb.dataset.nullToggle)}"]`)
      if (!input) return

      const syncStyle = () => {
        const isNull = cb.checked
        input.classList.toggle("bg-gray-50",   isNull)
        input.classList.toggle("text-gray-400", isNull)
        input.classList.toggle("italic",        isNull)
        input.placeholder = isNull ? "NULL" : ""
      }

      // Checking NULL: visually grey out + clear value
      cb.addEventListener("change", () => {
        if (cb.checked) input.value = ""
        syncStyle()
      })

      // Typing: auto-uncheck NULL
      input.addEventListener("input", () => {
        if (cb.checked && input.value !== "") {
          cb.checked = false
          syncStyle()
        }
      })

      // Apply initial visual state (no disabled — user can always type)
      syncStyle()
    })
  }
}

function esc(s) {
  return String(s)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;")
    .replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}
function attr(s) {
  return String(s).replace(/&/g, "&amp;").replace(/"/g, "&quot;")
}
