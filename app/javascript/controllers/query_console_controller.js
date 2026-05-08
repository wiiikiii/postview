import { Controller } from "@hotwired/stimulus"
import { prefGet, prefSet } from "lib/prefs"

const MAX_HISTORY = 50
const CDN = "https://cdn.jsdelivr.net/npm/codemirror@5.65.16"

export default class extends Controller {
  static targets = [
    "editorEl", "runBtn", "limitSelect", "results",
    "historyPanel", "historyList", "historyBadge", "historyChevron",
    "exportForm", "exportSql", "exportFmt",
    "schemaList", "schemaSearch",
  ]
  static values = {
    database:  String,
    tables:    Array,
    schemaUrl: String,   // template URL with literal __TABLE__ placeholder
  }

  #editor      = null
  #lastSql     = null
  #colCache    = {}      // table → columns array (lazy loaded)
  #expanded    = new Set()
  #filterQuery = ""
  #history     = []     // in-memory cache; loaded from server on connect

  connect() {
    this.#loadCodeMirror()
    this.#loadHistory()
    this.#renderSchema()
    this.schemaListTarget.addEventListener("click", e => this.#onSchemaClick(e))
  }

  // ── CodeMirror bootstrap ─────────────────────────────────────────────────

  async #loadCodeMirror() {
    if (!window.CodeMirror) {
      this.#injectCss(`${CDN}/lib/codemirror.min.css`, "cm-core-css")
      await this.#loadScript(`${CDN}/lib/codemirror.min.js`, "cm-core")
      await this.#loadScript(`${CDN}/mode/sql/sql.js`, "cm-sql")
      await Promise.all([
        this.#loadScript(`${CDN}/addon/edit/matchbrackets.js`, "cm-mb"),
        this.#loadScript(`${CDN}/addon/comment/comment.js`,    "cm-comment"),
        this.#loadScript(`${CDN}/addon/display/placeholder.js`, "cm-ph"),
      ])
    }
    this.#editor = window.CodeMirror(this.editorElTarget, {
      mode:          "text/x-sql",
      lineNumbers:   true,
      matchBrackets: true,
      placeholder:   "SELECT * FROM tabelle LIMIT 100;",
      extraKeys: {
        "Ctrl-Enter": () => this.run(),
        "Cmd-Enter":  () => this.run(),
        "Ctrl-/":     cm => cm.execCommand("toggleComment"),
        "Cmd-/":      cm => cm.execCommand("toggleComment"),
      },
    })
  }

  #injectCss(href, id) {
    if (document.getElementById(id)) return
    const link = Object.assign(document.createElement("link"), { rel: "stylesheet", href, id })
    document.head.appendChild(link)
  }

  #loadScript(src, id) {
    if (document.getElementById(id)) return Promise.resolve()
    return new Promise((resolve, reject) => {
      const s = Object.assign(document.createElement("script"), { src, id })
      s.onload = resolve
      s.onerror = reject
      document.head.appendChild(s)
    })
  }

  // ── Run query ────────────────────────────────────────────────────────────

  async run() {
    const sql = (this.#editor?.getSelection().trim() || this.#editor?.getValue().trim())
    if (!sql) return
    this.#lastSql = sql

    this.runBtnTarget.disabled = true
    this.runBtnTarget.innerHTML = this.#spinnerHtml("Wird ausgeführt…")

    try {
      const resp = await fetch(
        `/databases/${enc(this.databaseValue)}/query`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/x-www-form-urlencoded",
            "X-CSRF-Token": csrf(),
            "Accept":       "application/json",
          },
          body: new URLSearchParams({ sql, limit: this.limitSelectTarget.value }),
        }
      )
      const data = await resp.json()
      if (resp.ok) {
        await this.#addToHistory({ sql, elapsed: data.elapsed, count: data.count, ts: Date.now() })
        this.#renderSuccess(data, sql)
      } else {
        this.#renderError(data.error, data.elapsed, sql)
      }
    } catch (e) {
      this.#renderError(e.message, null, sql)
    } finally {
      this.runBtnTarget.disabled = false
      this.runBtnTarget.innerHTML = this.#runBtnHtml()
    }
  }

  // ── Export ───────────────────────────────────────────────────────────────

  exportCsv()  { this.#export("csv")  }
  exportJson() { this.#export("json") }

  #export(fmt) {
    const sql = this.#lastSql || this.#editor?.getValue().trim()
    if (!sql) return
    this.exportSqlTarget.value = sql
    this.exportFmtTarget.value = fmt
    this.exportFormTarget.submit()
  }

  // ── History ──────────────────────────────────────────────────────────────

  toggleHistory() {
    const hidden = this.historyPanelTarget.classList.toggle("hidden")
    this.historyChevronTarget.style.transform = hidden ? "" : "rotate(180deg)"
  }

  async clearHistory() {
    this.#history = []
    await prefSet(this.#histKey, [])
    this.#renderHistory()
  }

  async #loadHistory() {
    const stored = await prefGet(this.#histKey)
    this.#history = Array.isArray(stored) ? stored : []
    this.#renderHistory()
  }

  async #addToHistory(entry) {
    if (this.#history[0]?.sql === entry.sql) {
      this.#history[0] = entry
    } else {
      this.#history.unshift(entry)
    }
    this.#history.splice(MAX_HISTORY)
    await prefSet(this.#histKey, this.#history)
    this.#renderHistory()
  }

  #renderHistory() {
    const history = this.#history
    this.historyBadgeTarget.textContent = history.length

    if (history.length === 0) {
      this.historyListTarget.innerHTML =
        `<p class="px-4 py-8 text-center text-sm text-gray-400">Noch keine Abfragen ausgeführt</p>`
      return
    }

    this.historyListTarget.innerHTML = history.map((entry, idx) => `
      <div class="flex items-start gap-3 px-4 py-3 hover:bg-gray-50 group">
        <div class="flex-1 min-w-0 cursor-pointer" data-history-idx="${idx}">
          <p class="font-mono text-xs text-gray-700 truncate">${esc(entry.sql)}</p>
          <p class="text-xs text-gray-400 mt-0.5 tabular-nums">
            ${new Date(entry.ts).toLocaleString("de-CH")}
            ${entry.count != null ? ` &middot; ${entry.count} Z.` : ""}
            ${entry.elapsed  != null ? ` &middot; ${entry.elapsed}s` : ""}
          </p>
        </div>
        <button class="shrink-0 mt-0.5 opacity-0 group-hover:opacity-100 transition-opacity
                       text-xs text-sky-500 hover:text-sky-700"
                data-history-idx="${idx}">Laden</button>
      </div>`).join("")

    this.historyListTarget.onclick = e => {
      const el = e.target.closest("[data-history-idx]")
      if (!el) return
      const entry = this.#history[+el.dataset.historyIdx]
      if (entry) { this.#editor?.setValue(entry.sql); this.#editor?.focus() }
    }
  }

  get #histKey() {
    return `qhist:${this.databaseValue}`
  }

  // ── Schema sidebar ───────────────────────────────────────────────────────

  filterSchema() {
    this.#filterQuery = this.schemaSearchTarget.value.trim().toLowerCase()
    this.#renderSchema()
  }

  #renderSchema() {
    const tables  = this.tablesValue
    const q       = this.#filterQuery
    const visible = q ? tables.filter(t => t.toLowerCase().includes(q)) : tables

    if (visible.length === 0) {
      this.schemaListTarget.innerHTML =
        `<p class="px-4 py-6 text-center text-gray-400">Keine Tabellen gefunden</p>`
      return
    }

    this.schemaListTarget.innerHTML = visible.map(table => {
      const open = this.#expanded.has(table)
      return `
        <div data-schema-table="${esc(table)}">
          <div class="flex items-center gap-1 px-2 py-1.5 hover:bg-sky-50 cursor-pointer group"
               data-schema-toggle="${esc(table)}">
            <svg class="h-3.5 w-3.5 shrink-0 text-gray-300 transition-transform duration-150 ${open ? "rotate-90" : ""}"
                 data-schema-chevron="${esc(table)}"
                 fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" d="m8.25 4.5 7.5 7.5-7.5 7.5" />
            </svg>
            <span class="flex-1 font-mono text-xs font-medium text-gray-700 truncate
                         group-hover:text-sky-700 cursor-pointer"
                  data-schema-insert="${esc(table)}">${esc(table)}</span>
            <button class="shrink-0 opacity-0 group-hover:opacity-100 transition-opacity
                           text-gray-300 hover:text-sky-500 px-1"
                    title="SELECT * FROM ${esc(table)}"
                    data-schema-select="${esc(table)}">
              <svg class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round"
                      d="M5.25 5.653c0-.856.917-1.398 1.667-.986l11.54 6.347a1.125 1.125 0 0 1 0 1.972l-11.54 6.347a1.125 1.125 0 0 1-1.667-.986V5.653Z"/>
              </svg>
            </button>
          </div>
          <div data-schema-cols="${esc(table)}" class="${open ? "" : "hidden"}">
            ${open && this.#colCache[table] ? this.#colsHtml(this.#colCache[table]) : ""}
          </div>
        </div>`
    }).join("")
  }

  async #onSchemaClick(e) {
    const selBtn = e.target.closest("[data-schema-select]")
    if (selBtn) {
      this.#setEditorValue(`SELECT *\nFROM   ${selBtn.dataset.schemaSelect}\nLIMIT  100;`)
      return
    }

    const ins = e.target.closest("[data-schema-insert]")
    if (ins && !e.target.closest("[data-schema-toggle]")) {
      this.#insertAtCursor(ins.dataset.schemaInsert)
      return
    }

    const col = e.target.closest("[data-schema-col]")
    if (col) {
      this.#insertAtCursor(col.dataset.schemaCol)
      return
    }

    const toggle = e.target.closest("[data-schema-toggle]")
    if (toggle) {
      await this.#toggleTable(toggle.dataset.schemaToggle)
    }
  }

  async #toggleTable(table) {
    const colsEl  = this.schemaListTarget.querySelector(`[data-schema-cols="${CSS.escape(table)}"]`)
    const chevron = this.schemaListTarget.querySelector(`[data-schema-chevron="${CSS.escape(table)}"]`)
    if (!colsEl) return

    const isOpen = !colsEl.classList.contains("hidden")
    if (isOpen) {
      colsEl.classList.add("hidden")
      chevron?.classList.remove("rotate-90")
      this.#expanded.delete(table)
      return
    }

    this.#expanded.add(table)
    chevron?.classList.add("rotate-90")

    if (!this.#colCache[table]) {
      colsEl.innerHTML = `<div class="px-6 py-2 text-gray-400 text-xs">Lade…</div>`
      colsEl.classList.remove("hidden")
      try {
        const url  = this.schemaUrlValue.replace("__TABLE__", encodeURIComponent(table))
        const resp = await fetch(url, { headers: { Accept: "application/json" } })
        this.#colCache[table] = resp.ok ? await resp.json() : []
      } catch {
        this.#colCache[table] = []
      }
    }

    colsEl.innerHTML = this.#colsHtml(this.#colCache[table])
    colsEl.classList.remove("hidden")
  }

  #colsHtml(cols) {
    if (!cols.length) {
      return `<div class="px-6 py-2 text-gray-400 text-xs italic">Keine Spalten</div>`
    }
    return cols.map(c => {
      const pkBadge  = c.pk
        ? `<svg class="h-3 w-3 text-amber-400 shrink-0" fill="currentColor" viewBox="0 0 20 20">
             <path fill-rule="evenodd" d="M8 7a5 5 0 1 1 3.536 4.75l-1.122 1.12A1 1 0 0 1 9.707 13H9v.707a1 1 0 0 1-.293.707L8 15.121V16H7a1 1 0 0 1-1-1v-1.586l-.121-.121A1 1 0 0 1 5.586 13H5v-.707a1 1 0 0 1 .293-.707l4.171-4.17A5.02 5.02 0 0 1 8 7Zm2-3a1 1 0 1 0 0 2 1 1 0 0 0 0-2Z" clip-rule="evenodd"/>
           </svg>`
        : `<span class="h-3 w-3 shrink-0"></span>`
      const nullable = c.nullable
        ? `<span class="text-gray-300" title="NULL erlaubt">?</span>`
        : ""
      const typeStr  = shortType(c.sql_type)
      return `
        <div class="flex items-center gap-1.5 px-5 py-1 hover:bg-sky-50 cursor-pointer group"
             data-schema-col="${esc(c.name)}"
             title="${esc(c.name)} · ${esc(c.sql_type)}${c.nullable ? " · nullable" : ""}${c.pk ? " · PK" : ""}">
          ${pkBadge}
          <span class="flex-1 font-mono text-xs text-gray-600 group-hover:text-sky-700 truncate">
            ${esc(c.name)}${nullable}
          </span>
          <span class="shrink-0 text-gray-300 text-xs font-mono">${esc(typeStr)}</span>
        </div>`
    }).join("")
  }

  // ── Editor helpers ───────────────────────────────────────────────────────

  #insertAtCursor(text) {
    if (!this.#editor) return
    this.#editor.focus()
    const cursor = this.#editor.getCursor()
    const line   = this.#editor.getLine(cursor.line)
    const prefix = cursor.ch > 0 && /\S/.test(line[cursor.ch - 1]) ? " " : ""
    this.#editor.replaceRange(prefix + text, cursor)
  }

  #setEditorValue(sql) {
    if (!this.#editor) return
    this.#editor.setValue(sql)
    this.#editor.focus()
    this.#editor.setCursor(this.#editor.lineCount(), 0)
  }

  // ── Result rendering ─────────────────────────────────────────────────────

  #renderSuccess({ columns, rows, elapsed, count, limited, status }, sql) {
    if (!columns || columns.length === 0) {
      this.resultsTarget.innerHTML = `
        <div class="bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden">
          ${this.#sqlBanner(sql)}
          <div class="px-5 py-4 flex items-center gap-3">
            <span class="h-2 w-2 rounded-full bg-green-400 shrink-0"></span>
            <span class="text-sm font-medium text-gray-700">${esc(status)}</span>
            ${elapsed != null ? `<span class="ml-auto text-xs text-gray-400 tabular-nums">${elapsed}s</span>` : ""}
          </div>
        </div>`
      this.resultsTarget.classList.remove("hidden")
      return
    }

    const header = columns.map(c =>
      `<th class="px-3 py-2.5 text-left text-xs font-medium text-gray-500 whitespace-nowrap
                  border-b border-gray-200 bg-gray-50 sticky top-0 z-10">${esc(c)}</th>`
    ).join("")

    const body = rows.map(row =>
      `<tr class="hover:bg-sky-50 transition-colors">
        ${columns.map(c => {
          const v = row[c]
          return `<td class="px-3 py-2 border-b border-gray-50 max-w-xs">${
            v === null
              ? `<span class="text-gray-300 italic text-xs">NULL</span>`
              : `<span class="font-mono text-xs text-gray-700 break-all">${esc(String(v))}</span>`
          }</td>`
        }).join("")}
      </tr>`
    ).join("")

    this.resultsTarget.innerHTML = `
      <div class="bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden">
        ${this.#sqlBanner(sql)}
        <div class="flex items-center justify-between px-4 py-2.5 border-b border-gray-100 bg-gray-50">
          <div class="flex items-center gap-3">
            <span class="h-2 w-2 rounded-full bg-green-400 shrink-0"></span>
            <span class="text-sm text-gray-600">
              <strong class="text-gray-800">${count}</strong> Zeilen
              ${limited
                ? `<span class="text-amber-500 text-xs ml-1">(Anzeige limitiert auf ${rows.length})</span>`
                : ""}
            </span>
          </div>
          <div class="flex items-center gap-2">
            <span class="text-xs text-gray-400 tabular-nums mr-2">${elapsed}s</span>
            <button type="button" data-action="click->query-console#exportCsv"
                    class="inline-flex items-center gap-1 rounded-lg border border-gray-200
                           px-2.5 py-1 text-xs font-medium text-gray-600 hover:bg-gray-100 transition-colors">
              ${dlIcon()} CSV
            </button>
            <button type="button" data-action="click->query-console#exportJson"
                    class="inline-flex items-center gap-1 rounded-lg border border-gray-200
                           px-2.5 py-1 text-xs font-medium text-gray-600 hover:bg-gray-100 transition-colors">
              ${dlIcon()} JSON
            </button>
          </div>
        </div>
        <div class="overflow-x-auto" style="max-height:55vh;overflow-y:auto;">
          <table class="min-w-full text-sm">
            <thead><tr>${header}</tr></thead>
            <tbody class="divide-y divide-gray-50">${body}</tbody>
          </table>
        </div>
      </div>`
    this.resultsTarget.classList.remove("hidden")
    this.resultsTarget.scrollIntoView({ behavior: "smooth", block: "nearest" })
  }

  #renderError(msg, elapsed, sql) {
    this.resultsTarget.innerHTML = `
      <div class="border border-red-200 rounded-xl overflow-hidden">
        ${this.#sqlBanner(sql, true)}
        <div class="bg-red-50 px-4 py-3 flex items-start gap-3">
          <svg class="h-4 w-4 mt-0.5 shrink-0 text-red-400" fill="none" viewBox="0 0 24 24"
               stroke-width="1.5" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round"
                  d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0
                     2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898
                     0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z"/>
          </svg>
          <div class="flex-1 min-w-0">
            <p class="text-sm font-medium text-red-700 break-all">${esc(msg)}</p>
            ${elapsed != null ? `<p class="text-xs text-red-400 mt-1 tabular-nums">${elapsed}s</p>` : ""}
          </div>
        </div>
      </div>`
    this.resultsTarget.classList.remove("hidden")
  }

  // ── Shared result helpers ────────────────────────────────────────────────

  #sqlBanner(sql, error = false) {
    if (!sql) return ""
    const oneLine = sql.replace(/\s+/g, " ").trim()
    const bg      = error ? "bg-red-100 border-red-200" : "bg-gray-50 border-gray-100"
    const text    = error ? "text-red-600" : "text-gray-500"
    return `
      <div class="flex items-start gap-2 px-4 py-2 border-b ${bg}">
        <svg class="h-3.5 w-3.5 mt-0.5 shrink-0 ${text}" fill="none" viewBox="0 0 24 24"
             stroke-width="1.5" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round"
                d="M17.25 6.75 22.5 12l-5.25 5.25m-10.5 0L1.5 12l5.25-5.25m7.5-3-4.5 16.5"/>
        </svg>
        <code class="flex-1 font-mono text-xs ${text} break-all leading-relaxed">${esc(oneLine)}</code>
      </div>`
  }

  // ── Button HTML helpers ──────────────────────────────────────────────────

  #runBtnHtml() {
    return `<svg class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round"
                    d="M5.25 5.653c0-.856.917-1.398 1.667-.986l11.54 6.347a1.125 1.125 0 0 1
                       0 1.972l-11.54 6.347a1.125 1.125 0 0 1-1.667-.986V5.653Z"/>
            </svg>
            Ausführen
            <kbd class="hidden sm:inline-block text-xs font-sans opacity-60 bg-sky-500 rounded px-1">⌘↵</kbd>`
  }

  #spinnerHtml(label) {
    return `<svg class="h-3.5 w-3.5 animate-spin" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10"
                      stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z"></path>
            </svg> ${label}`
  }
}

// ── Module-level helpers ─────────────────────────────────────────────────────

function esc(s) {
  return String(s)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;")
    .replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}

function enc(s) { return encodeURIComponent(s) }

function csrf() {
  return document.querySelector('meta[name="csrf-token"]')?.content
}

function dlIcon() {
  return `<svg class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round"
                  d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5
                     M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3"/>
          </svg>`
}

function shortType(t) {
  const map = {
    "character varying": "varchar",
    "timestamp without time zone": "timestamp",
    "timestamp with time zone": "timestamptz",
    "double precision": "float8",
    "integer": "int4",
    "bigint": "int8",
    "smallint": "int2",
    "boolean": "bool",
    "character": "char",
  }
  const lower = (t || "").toLowerCase()
  for (const [long, short] of Object.entries(map)) {
    if (lower.startsWith(long)) return short
  }
  return t.length > 12 ? t.slice(0, 11) + "…" : t
}
