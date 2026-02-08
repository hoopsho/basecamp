// Generic conditional visibility controller
// Shows/hides its own element based on another field's value within the same form.
//
// Values:
//   when: Comma-separated list of values that cause this element to be shown
//   selector: CSS selector to find the controlling field (default: first <select> in the form)
//
// Usage:
//   <form>
//     <select name="step[step_type]">...</select>
//
//     <div data-controller="conditional-field"
//          data-conditional-field-when-value="llm_classify,llm_draft"
//          data-conditional-field-selector-value="select[name*='step_type']">
//       <!-- Content shown only when step_type matches -->
//     </div>
//   </form>

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    when: String,
    selector: { type: String, default: "" }
  }

  connect() {
    this.boundToggle = this.toggle.bind(this)

    const form = this.element.closest("form")
    if (!form) return

    if (this.selectorValue) {
      this.selectElement = form.querySelector(this.selectorValue)
    } else {
      this.selectElement = form.querySelector("select")
    }

    if (this.selectElement) {
      this.selectElement.addEventListener("change", this.boundToggle)
      this.toggle()
    }
  }

  disconnect() {
    if (this.selectElement) {
      this.selectElement.removeEventListener("change", this.boundToggle)
    }
  }

  toggle() {
    const currentValue = this.selectElement?.value || ""
    const allowedValues = this.whenValue.split(",").map(v => v.trim())
    const shouldShow = allowedValues.includes(currentValue)

    this.element.style.display = shouldShow ? "" : "none"
  }
}
