import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    setTimeout(() => {
      this.element.style.transition = "opacity 0.4s ease, transform 0.4s ease"
      this.element.style.opacity = "0"
      this.element.style.transform = "translateX(1rem)"
      setTimeout(() => this.element.remove(), 400)
    }, 2500)
  }
}
