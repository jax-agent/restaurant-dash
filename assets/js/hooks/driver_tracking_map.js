// DriverTrackingMap Hook — shows single driver on Leaflet map for customer order tracking
// Joins "order_tracking:{order_id}" channel via Phoenix socket and receives location updates.

import { Socket } from "phoenix"

const DriverTrackingMap = {
  mounted() {
    const L = window.L
    if (!L) {
      console.error("Leaflet not loaded")
      return
    }

    const orderId = this.el.dataset.orderId
    const initialLat = parseFloat(this.el.dataset.lat) || 37.7749
    const initialLng = parseFloat(this.el.dataset.lng) || -122.4194
    const hasDriver = this.el.dataset.hasDriver === "true"

    // Init map
    this.map = L.map(this.el, { zoomControl: true }).setView([initialLat, initialLng], 14)
    this.L = L

    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
      maxZoom: 19,
    }).addTo(this.map)

    // Driver marker
    this.driverMarker = null

    if (hasDriver) {
      this._placeDriverMarker(initialLat, initialLng)
    }

    // Join Phoenix channel for live updates
    if (orderId) {
      const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
      this.socket = new Socket("/socket", {})
      this.socket.connect()

      this.channel = this.socket.channel(`order_tracking:${orderId}`, {})
      this.channel.on("driver_location", (payload) => {
        this._updateDriverPosition(payload.lat, payload.lng)
      })
      this.channel.join()
    }
  },

  _placeDriverMarker(lat, lng) {
    const L = this.L
    const icon = L.divIcon({
      className: "",
      html: `<div style="
        width:36px; height:36px;
        background:#2563EB;
        border:3px solid white;
        border-radius:50%;
        box-shadow:0 2px 8px rgba(0,0,0,0.35);
        display:flex;
        align-items:center;
        justify-content:center;
        font-size:18px;
        transition:all 0.5s ease;
      ">🛵</div>`,
      iconSize: [36, 36],
      iconAnchor: [18, 18],
    })

    if (this.driverMarker) {
      this.driverMarker.setLatLng([lat, lng])
    } else {
      this.driverMarker = L.marker([lat, lng], { icon }).addTo(this.map)
      this.driverMarker.bindPopup("<b>Your driver</b><br>On the way!")
    }
  },

  _updateDriverPosition(lat, lng) {
    if (!this.L) return
    this._placeDriverMarker(lat, lng)
    // Smoothly pan map to follow driver
    this.map.panTo([lat, lng], { animate: true, duration: 0.5 })
  },

  destroyed() {
    if (this.channel) this.channel.leave()
    if (this.socket) this.socket.disconnect()
    if (this.map) { this.map.remove(); this.map = null }
  },
}

export default DriverTrackingMap
