import { Controller } from "@hotwired/stimulus"

// Generic chat UX controller
// Handles form submission state, auto-scroll, and input management
export default class extends Controller {
  static targets = ["log", "input", "submit", "form"]

  connect() {
    this.scrollToBottom()

    // Auto-scroll whenever Turbo Stream appends new children
    if (this.hasLogTarget) {
      this.observer = new MutationObserver(() => this.scrollToBottom())
      this.observer.observe(this.logTarget, { childList: true })
    }
  }

  disconnect() {
    this.observer?.disconnect()
  }

  onSubmitStart() {
    this.inputTarget.disabled = true
    this.submitTarget.disabled = true
    this.submitTarget.dataset.originalText = this.submitTarget.textContent
    this.submitTarget.textContent = "Thinking..."
  }

  onSubmitEnd() {
    this.inputTarget.disabled = false
    this.submitTarget.disabled = false
    this.submitTarget.textContent = this.submitTarget.dataset.originalText || "Send"
    this.inputTarget.value = ""
    this.inputTarget.focus()
    this.scrollToBottom()
  }

  scrollToBottom() {
    if (this.hasLogTarget) {
      // Small delay to allow DOM updates from Turbo Stream
      requestAnimationFrame(() => {
        this.logTarget.scrollTop = this.logTarget.scrollHeight
      })
    }
  }

  // Allow Enter to submit (Shift+Enter for newline)
  submitOnEnter(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      if (this.inputTarget.value.trim() !== "" && !this.submitTarget.disabled) {
        this.formTarget.requestSubmit()
      }
    }
  }
}
