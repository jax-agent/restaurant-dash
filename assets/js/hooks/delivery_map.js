// DeliveryMap LiveView hook — Leaflet + OpenStreetMap
// Renders markers for orders that are out_for_delivery.
// Listens to "update_marker" push events from the server.

import L from "leaflet"
import "leaflet/dist/leaflet.css"

// Fix Leaflet default icon paths (broken by bundlers)
delete L.Icon.Default.prototype._getIconUrl
L.Icon.Default.mergeOptions({
  iconRetinaUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png",
  iconUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png",
  shadowUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png",
})

const DeliveryMap = {
  mounted() {
    const primaryColor = this.el.dataset.primaryColor || "#E63946"
    const orders = JSON.parse(this.el.dataset.orders || "[]")

    // Init map centered on San Francisco
    this.map = L.map(this.el).setView([37.7749, -122.4194], 12)

    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
      maxZoom: 19,
    }).addTo(this.map)

    this.markers = {}
    this.primaryColor = primaryColor

    // Add initial markers
    orders.forEach(order => this._addOrUpdateMarker(order))

    // Listen for server push events to update marker positions
    this.handleEvent("update_marker", (data) => {
      this._addOrUpdateMarker(data)
    })
  },

  updated() {
    // When the element is updated (phx-update="ignore" prevents this, but just in case)
    const orders = JSON.parse(this.el.dataset.orders || "[]")
    const existingIds = new Set(Object.keys(this.markers).map(Number))
    const newIds = new Set(orders.map(o => o.id))

    // Remove markers for delivered/gone orders
    existingIds.forEach(id => {
      if (!newIds.has(id)) {
        this.map.removeLayer(this.markers[id])
        delete this.markers[id]
      }
    })

    // Add/update markers for active deliveries
    orders.forEach(order => this._addOrUpdateMarker(order))
  },

  destroyed() {
    if (this.map) {
      this.map.remove()
      this.map = null
    }
  },

  _addOrUpdateMarker(order) {
    if (!order.lat || !order.lng) return

    const popupContent = this._buildPopup(order)

    if (this.markers[order.id]) {
      // Smooth-ish move: just set new lat/lng
      this.markers[order.id]
        .setLatLng([order.lat, order.lng])
        .setPopupContent(popupContent)
    } else {
      const marker = L.marker([order.lat, order.lng], {
        icon: this._createIcon(),
      })
        .addTo(this.map)
        .bindPopup(popupContent)

      this.markers[order.id] = marker
    }
  },

  _createIcon() {
    return L.divIcon({
      className: "",
      html: `<div style="
        width: 32px; height: 32px;
        background: ${this.primaryColor};
        border: 3px solid white;
        border-radius: 50%;
        box-shadow: 0 2px 6px rgba(0,0,0,0.3);
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 14px;
      ">🛵</div>`,
      iconSize: [32, 32],
      iconAnchor: [16, 16],
      popupAnchor: [0, -20],
    })
  },

  _buildPopup(order) {
    const items = (order.items || []).join(", ") || "—"
    return `
      <div style="min-width:180px; font-family: -apple-system, sans-serif;">
        <div style="font-weight:600; font-size:14px; margin-bottom:4px;">
          ${order.customer_name}
        </div>
        <div style="font-size:12px; color:#6b7280; margin-bottom:4px;">
          ${order.delivery_address || ""}
        </div>
        <div style="font-size:12px; margin-bottom:4px;">
          🍕 ${items}
        </div>
        <div style="font-size:11px; color:#10b981; font-weight:600;">
          🟢 Out for Delivery
        </div>
      </div>
    `
  },
}

export default DeliveryMap
