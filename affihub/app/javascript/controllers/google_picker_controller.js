import { Controller } from "@hotwired/stimulus"
import "@googleworkspace/drive-picker-element"

export default class extends Controller {
  static targets = ["form", "host", "spreadsheetId", "status"]
  static values = {
    appId: String,
    clientId: String,
    developerKey: String,
    scope: String,
    spreadsheetMimeType: String
  }

  /**
   * Opens Google Picker only after the user requests it.
   * @param {Event} event The button activation event.
   */
  open(event) {
    event.preventDefault()
    this.removePicker()
    this.statusTarget.textContent = "Đang mở Google Picker…"

    const picker = document.createElement("drive-picker")
    picker.setAttribute("app-id", this.appIdValue)
    picker.setAttribute("client-id", this.clientIdValue)
    picker.setAttribute("developer-key", this.developerKeyValue)
    picker.setAttribute("scope", this.scopeValue)
    picker.setAttribute("locale", "vi")
    picker.setAttribute("max-items", "1")

    const spreadsheetView = document.createElement("drive-picker-docs-view")
    spreadsheetView.setAttribute("view-id", "DOCS")
    spreadsheetView.setAttribute("mime-types", this.spreadsheetMimeTypeValue)
    spreadsheetView.setAttribute("include-folders", "false")
    picker.append(spreadsheetView)

    picker.addEventListener("picker-picked", (pickerEvent) => this.handlePicked(pickerEvent), { once: true })
    picker.addEventListener("picker-canceled", () => this.handleCanceled(), { once: true })
    picker.addEventListener("picker-error", () => this.handlePickerError(), { once: true })
    picker.addEventListener("picker-oauth-error", () => this.handlePickerOAuthError(), { once: true })

    this.picker = picker
    this.hostTarget.append(picker)
  }

  /**
   * Removes the Google Picker custom element when this controller disconnects.
   */
  disconnect() {
    this.removePicker()
  }

  /**
   * Submits the picked spreadsheet ID to the existing settings GET route.
   * @param {CustomEvent} event The Google Picker response event.
   */
  handlePicked(event) {
    const spreadsheetId = event.detail?.docs?.[0]?.id
    this.removePicker()

    if (!spreadsheetId) {
      this.statusTarget.textContent = "Google Picker không trả về mã bảng tính. Hãy chọn lại."
      return
    }

    this.spreadsheetIdTarget.value = spreadsheetId
    this.statusTarget.textContent = "Đang xác minh bảng tính và tải danh sách tab…"
    this.formTarget.requestSubmit()
  }

  /**
   * Reports that the user closed Google Picker without changing settings.
   */
  handleCanceled() {
    this.removePicker()
    this.statusTarget.textContent = "Bạn đã đóng Google Picker. Cấu hình chưa thay đổi."
  }

  /**
   * Shows a safe message when Google Picker reports an error.
   */
  handlePickerError() {
    this.removePicker()
    this.statusTarget.textContent = "Không mở được Google Picker. Hãy thử lại sau."
  }

  /**
   * Shows a safe message when Google Identity Services declines Picker access.
   */
  handlePickerOAuthError() {
    this.removePicker()
    this.statusTarget.textContent = "Google chưa cấp quyền để mở Picker. Hãy kiểm tra kết nối rồi thử lại."
  }

  /**
   * Removes the active Picker, disposing the third-party custom element.
   */
  removePicker() {
    this.picker?.remove()
    this.picker = null
  }
}
