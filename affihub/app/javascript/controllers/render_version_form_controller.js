import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  /**
   * Adds an editing row to the selected collection.
   *
   * @param {Event} event the add button event
   * @returns {void}
   */
  add(event) {
    const collectionName = event.currentTarget.dataset.collectionTarget
    const templateName = event.currentTarget.dataset.templateTarget
    const collection = this.element.querySelector(`[data-render-version-form-target="${collectionName}"]`)
    const template = this.element.querySelector(`[data-render-version-form-target="${templateName}"]`)

    if (!collection || !template) return

    collection.append(template.content.cloneNode(true))
  }

  /**
   * Removes the editing row that contains the clicked button.
   *
   * @param {Event} event the remove button event
   * @returns {void}
   */
  remove(event) {
    const row = event.currentTarget.closest("[data-editor-item]")

    if (row) row.remove()
  }
}
