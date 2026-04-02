/**
 * KdsAudio — audio alerts for the Kitchen Display System.
 *
 * Uses the Web Audio API to generate tones without requiring audio files.
 * Browser requires a user gesture before audio can play — this hook handles
 * the "audio context suspended" state and resumes on first interaction.
 *
 * Sounds:
 *   new_order  — gentle chime (two ascending tones)
 *   overdue    — urgent buzzer (louder, lower frequency, repeating)
 *
 * Listens for:
 *   phx:new_order_alert  — play new order sound
 */
const KdsAudio = {
  mounted() {
    this.audioCtx = null
    this.muted = this.el.dataset.muted === "true"

    // Resume audio context on first user interaction (browser policy)
    this._resumeOnClick = () => this._ensureAudioCtx()
    document.addEventListener("click", this._resumeOnClick, { once: true })
    document.addEventListener("keydown", this._resumeOnClick, { once: true })

    // Listen for server-pushed audio events
    this.handleEvent("new_order_alert", ({ muted }) => {
      if (!muted) this.playNewOrderChime()
    })

    // Signal to server that audio hook is ready
    this.pushEvent("audio_ready", {})
  },

  updated() {
    this.muted = this.el.dataset.muted === "true"
  },

  destroyed() {
    if (this.audioCtx) {
      this.audioCtx.close()
    }
  },

  _ensureAudioCtx() {
    if (!this.audioCtx) {
      this.audioCtx = new (window.AudioContext || window.webkitAudioContext)()
    }
    if (this.audioCtx.state === "suspended") {
      this.audioCtx.resume()
    }
    return this.audioCtx
  },

  playNewOrderChime() {
    if (this.muted) return
    const ctx = this._ensureAudioCtx()
    if (!ctx) return

    // Two ascending chime tones
    this._playTone(ctx, 523.25, 0.0, 0.15, 0.3) // C5
    this._playTone(ctx, 659.25, 0.2, 0.15, 0.3) // E5
    this._playTone(ctx, 783.99, 0.4, 0.15, 0.4) // G5
  },

  playOverdueAlert() {
    if (this.muted) return
    const ctx = this._ensureAudioCtx()
    if (!ctx) return

    // Low buzzer — three quick pulses
    for (let i = 0; i < 3; i++) {
      this._playTone(ctx, 180, i * 0.3, 0.3, 0.25, "sawtooth")
    }
  },

  _playTone(ctx, frequency, startOffset, duration, gain = 0.3, type = "sine") {
    const now = ctx.currentTime
    const osc = ctx.createOscillator()
    const gainNode = ctx.createGain()

    osc.type = type
    osc.frequency.setValueAtTime(frequency, now + startOffset)

    gainNode.gain.setValueAtTime(0, now + startOffset)
    gainNode.gain.linearRampToValueAtTime(gain, now + startOffset + 0.02)
    gainNode.gain.exponentialRampToValueAtTime(0.001, now + startOffset + duration)

    osc.connect(gainNode)
    gainNode.connect(ctx.destination)

    osc.start(now + startOffset)
    osc.stop(now + startOffset + duration)
  },
}

export default KdsAudio
