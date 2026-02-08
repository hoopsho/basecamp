import { Controller } from "@hotwired/stimulus"

// Toggle controller for show/hide functionality
// Usage:
// <div data-controller="toggle" data-toggle-active-class="hidden">
//   <button data-action="click->toggle#toggle" data-toggle-target="button">Toggle</button>
//   <div data-toggle-target="content" class="hidden">Content to toggle</div>
// </div>

export default class extends Controller {
  static targets = ["button", "content"]
  static values = {
    activeClass: { type: String, default: "hidden" }
  }

  connect() {
    // Initialize
  }

  toggle(event) {
    event?.preventDefault()
    event?.stopPropagation()

    this.contentTargets.forEach(content => {
      content.classList.toggle(this.activeClassValue)
    })

    // Update button aria-expanded for accessibility
    if (this.hasButtonTarget) {
      const isExpanded = this.buttonTarget.getAttribute("aria-expanded") === "true"
      this.buttonTarget.setAttribute("aria-expanded", !isExpanded)
    }
  }

  show() {
    this.contentTargets.forEach(content => {
      content.classList.remove(this.activeClassValue)
    })
    if (this.hasButtonTarget) {
      this.buttonTarget.setAttribute("aria-expanded", "true")
    }
  }

  hide() {
    this.contentTargets.forEach(content => {
      content.classList.add(this.activeClassValue)
    })
    if (this.hasButtonTarget) {
      this.buttonTarget.setAttribute("aria-expanded", "false")
    }
  }

  // Close when clicking outside
  hideOnClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.hide()
    }
  }
}
