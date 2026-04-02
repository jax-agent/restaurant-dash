/**
 * KdsKeyboard — bump-bar style keyboard shortcuts for the Kitchen Display System.
 *
 * Shortcuts (when no modal is open):
 *   Enter  — Accept the first "new" order
 *   Space  — Mark the first "preparing" order as ready
 *   Escape — Reject the first "new" order (with confirmation)
 *
 * Shortcuts (when modal is open):
 *   Enter  — Click the primary action button in the modal
 *   Escape — Close the modal
 */
const KdsKeyboard = {
  mounted() {
    this._handler = (e) => this.handleKey(e)
    document.addEventListener("keydown", this._handler)
  },

  destroyed() {
    document.removeEventListener("keydown", this._handler)
  },

  handleKey(e) {
    // Don't intercept when user is typing in inputs
    if (["INPUT", "TEXTAREA", "SELECT"].includes(e.target.tagName)) return

    const modal = document.getElementById("kds-modal")
    const modalOpen = modal != null

    if (modalOpen) {
      this.handleModalKey(e, modal)
    } else {
      this.handleBoardKey(e)
    }
  },

  handleBoardKey(e) {
    switch (e.key) {
      case "Enter": {
        // Accept the first "new" order
        e.preventDefault()
        const btn = document.querySelector(
          '#kds-col-new .kds-btn--accept[phx-click="accept_order"]'
        )
        if (btn) btn.click()
        break
      }

      case " ": {
        // Mark first "preparing" order as ready
        e.preventDefault()
        const btn = document.querySelector(
          '#kds-col-preparing .kds-btn--ready[phx-click="mark_ready"]'
        )
        if (btn) btn.click()
        break
      }

      case "Escape": {
        // Reject the first "new" order
        e.preventDefault()
        const btn = document.querySelector(
          '#kds-col-new .kds-btn--reject[phx-click="reject_order"]'
        )
        if (btn) btn.click()
        break
      }
    }
  },

  handleModalKey(e, modal) {
    switch (e.key) {
      case "Enter": {
        e.preventDefault()
        // Click the first primary action button in the modal actions area
        const btn = modal.querySelector(
          ".kds-modal-actions .kds-btn--accept, " +
          ".kds-modal-actions .kds-btn--prepare, " +
          ".kds-modal-actions .kds-btn--ready"
        )
        if (btn) btn.click()
        break
      }

      case "Escape": {
        e.preventDefault()
        const closeBtn = modal.querySelector(".kds-modal-close")
        if (closeBtn) closeBtn.click()
        break
      }
    }
  },
}

export default KdsKeyboard
