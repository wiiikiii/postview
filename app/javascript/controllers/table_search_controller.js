import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropdown", "allCheckbox", "columnCheckbox", "hiddenInputs", "badge"]
  static values = {
    database: String,
    table: String,
    debounce: { type: Number, default: 300 }
  }

  #timer = null
  #outsideClick = (e) => { if (!this.element.contains(e.target)) this.#closeDropdown() }

  connect() {
    document.addEventListener("click", this.#outsideClick)
    this.#loadSettings()
  }

  disconnect() {
    document.removeEventListener("click", this.#outsideClick)
  }

  scheduleSubmit() {
    clearTimeout(this.#timer)
    this.#timer = setTimeout(() => this.element.requestSubmit(), this.debounceValue)
  }

  toggleDropdown(e) {
    e.stopPropagation()
    this.dropdownTarget.classList.toggle("hidden")
  }

  toggleAll(e) {
    this.columnCheckboxTargets.forEach(cb => { cb.checked = e.target.checked })
    this.#syncColumns()
  }

  toggleColumn() {
    const all = this.columnCheckboxTargets.every(cb => cb.checked)
    const any = this.columnCheckboxTargets.some(cb => cb.checked)
    this.allCheckboxTarget.checked = all
    this.allCheckboxTarget.indeterminate = !all && any

    this.#syncColumns()
  }

  #syncColumns() {
    this.#updateHiddenInputs()
    this.#updateBadge()
    this.#saveSettings()
  }

  #closeDropdown() {
    this.dropdownTarget.classList.add("hidden")
  }

  #updateHiddenInputs() {
    this.hiddenInputsTarget.innerHTML = ""
    if (this.columnCheckboxTargets.every(cb => cb.checked)) return

    this.columnCheckboxTargets
      .filter(cb => cb.checked)
      .forEach(cb => {
        const input = document.createElement("input")
        input.type = "hidden"
        input.name = "columns[]"
        input.value = cb.value
        this.hiddenInputsTarget.appendChild(input)
      })
  }

  #updateBadge() {
    const total = this.columnCheckboxTargets.length
    const checked = this.columnCheckboxTargets.filter(cb => cb.checked).length

    if (this.hasBadgeTarget) {
      this.badgeTarget.textContent = checked === total ? "Alle" : `${checked} / ${total}`
      this.badgeTarget.classList.toggle("text-sky-600", checked !== total)
      this.badgeTarget.classList.toggle("text-gray-500", checked === total)
    }
  }

  #saveSettings() {
    const selected = this.columnCheckboxTargets.filter(cb => cb.checked).map(cb => cb.value)
    localStorage.setItem(this.#key, JSON.stringify(selected))
  }

  #loadSettings() {
    try {
      const raw = localStorage.getItem(this.#key)
      if (!raw) return

      const selected = new Set(JSON.parse(raw))
      this.columnCheckboxTargets.forEach(cb => { cb.checked = selected.has(cb.value) })
      const all = this.columnCheckboxTargets.every(cb => cb.checked)
      const any = this.columnCheckboxTargets.some(cb => cb.checked)
      this.allCheckboxTarget.checked = all
      this.allCheckboxTarget.indeterminate = !all && any

      this.#updateHiddenInputs()
      this.#updateBadge()
    } catch (_) {}
  }

  get #key() {
    return `postview:${this.databaseValue}:${this.tableValue}:columns`
  }
}
