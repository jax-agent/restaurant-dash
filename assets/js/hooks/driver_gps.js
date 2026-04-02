// DriverGPS Hook — sends driver GPS via Phoenix Channel
// Attached to a hidden element on the driver dashboard.
// Uses navigator.geolocation.watchPosition to get real-time location.
// Connects to "driver_location:{driver_id}" channel and pushes updates.

import { Socket } from "phoenix"

const DriverGPS = {
  mounted() {
    const driverId = parseInt(this.el.dataset.driverId)
    const orderId = this.el.dataset.orderId ? parseInt(this.el.dataset.orderId) : null
    const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

    if (!driverId) return

    // Connect to the UserSocket
    this.socket = new Socket("/socket", { params: { driver_id: driverId } })
    this.socket.connect()

    this.channel = this.socket.channel(`driver_location:${driverId}`, {})
    this.channel.join()
      .receive("ok", () => console.log("GPS channel joined"))
      .receive("error", (resp) => console.error("GPS channel error", resp))

    // Start watching position
    if (navigator.geolocation) {
      this.watchId = navigator.geolocation.watchPosition(
        (position) => {
          const { latitude, longitude } = position.coords
          this.channel.push("update_location", {
            driver_id: driverId,
            lat: latitude,
            lng: longitude,
            order_id: orderId,
          })
        },
        (err) => console.warn("GPS error:", err),
        {
          enableHighAccuracy: true,
          maximumAge: 5000,
          timeout: 10000,
        }
      )
    }
  },

  updated() {
    // Update order_id if it changes (new delivery assigned)
    const orderId = this.el.dataset.orderId ? parseInt(this.el.dataset.orderId) : null
    this._orderId = orderId
  },

  destroyed() {
    if (this.watchId) {
      navigator.geolocation.clearWatch(this.watchId)
    }
    if (this.channel) {
      this.channel.leave()
    }
    if (this.socket) {
      this.socket.disconnect()
    }
  },
}

export default DriverGPS
