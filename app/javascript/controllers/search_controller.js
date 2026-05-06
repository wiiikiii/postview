import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "item", "empty", "count"]
  static values = { debounce: { type: Number, default: 200 } }

  #timer = null

  filter() {
    clearTimeout(this.#timer)
    this.#timer = setTimeout(() => this.#apply(), this.debounceValue)
  }

  #apply() {
    const q = this.inputTarget.value.trim().toLowerCase()
    let visible = 0

    this.itemTargets.forEach(el => {
      const match = !q || el.dataset.name.toLowerCase().includes(q)
      el.classList.toggle("hidden", !match)
      if (match) visible++
    })

    if (this.hasEmptyTarget) {
      this.emptyTarget.classList.toggle("hidden", visible > 0)
    }

    if (this.hasCountTarget) {
      this.countTarget.textContent = q
        ? `${visible} von ${this.itemTargets.length}`
        : this.itemTargets.length
    }
  }
}
