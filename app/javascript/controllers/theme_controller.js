import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { default: { type: String, default: "system" } }

  connect() {
    this.applyTheme(this.currentTheme)
  }

  toggle(event) {
    const theme = event.params.theme || this.nextTheme
    localStorage.setItem("theme", theme)
    this.applyTheme(theme)
  }

  get currentTheme() {
    return localStorage.getItem("theme") || this.defaultValue
  }

  get nextTheme() {
    const themes = ["light", "dark", "system"]
    const current = themes.indexOf(this.currentTheme)
    return themes[(current + 1) % themes.length]
  }

  applyTheme(theme) {
    const isDark = theme === "dark" ||
      (theme === "system" && window.matchMedia("(prefers-color-scheme: dark)").matches)
    document.documentElement.classList.toggle("dark", isDark)
  }
}
