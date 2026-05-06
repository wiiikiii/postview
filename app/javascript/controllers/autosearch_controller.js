import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { debounce: { type: Number, default: 300 } }

  #timer = null

  schedule() {
    clearTimeout(this.#timer)
    this.#timer = setTimeout(() => this.element.requestSubmit(), this.debounceValue)
  }
}
