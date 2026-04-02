# RestaurantDash

A white-label restaurant delivery dashboard built with **Phoenix LiveView**, **Oban**, and **Leaflet + OpenStreetMap**. Real-time Kanban board showing orders flowing from "New" → "Preparing" → "Out for Delivery" → "Delivered", with live delivery tracking on a map.

---

## Demo

> **Live app:** https://restaurant-dash.fly.dev

![Dashboard Screenshot](docs/screenshot.png)

### Features

- 🗂 **Real-time Kanban board** — orders grouped by status, live-updating via PubSub
- 🗺 **Live delivery map** — Leaflet + OpenStreetMap showing active deliveries with animated driver movement
- ⚡ **Oban lifecycle pipeline** — automatic order status transitions on schedule
- 🎨 **White-label config** — restaurant name, color, and logo via env vars
- 📱 **Mobile responsive** — stacked layout on small screens
- ➕ **New Order form** — modal with real-time validation, schedules lifecycle automatically

---

## Stack

| Layer | Technology |
|-------|-----------|
| Language | Elixir 1.19 |
| Web | Phoenix 1.8 + LiveView |
| Jobs | Oban 2.x (open-source) |
| DB | PostgreSQL (Ecto) |
| Map | Leaflet + OpenStreetMap |
| CSS | Tailwind CSS v4 + DaisyUI |
| Deploy | Fly.io |

---

## Development Setup

### Prerequisites

- Elixir 1.15+
- PostgreSQL running locally
- Node.js (for asset bundling)

### Steps

```bash
# Clone the repo
git clone https://github.com/jax-agent/restaurant-dash.git
cd restaurant-dash

# Install dependencies
mix setup

# Start the server
mix phx.server
```

Visit [`http://localhost:4000`](http://localhost:4000) — dashboard loads with demo data.

### Seeding demo orders

```bash
mix run priv/repo/seeds.exs
```

---

## White-Label Configuration

Set these env vars to brand for any restaurant:

| Env Var | Default | Description |
|---------|---------|-------------|
| `RESTAURANT_NAME` | `Sal's Pizza` | Shown in header and page title |
| `PRIMARY_COLOR` | `#E63946` | Hex color for header, buttons, accents |
| `LOGO_URL` | `🍕` | Emoji or URL for the logo |

Example:

```bash
RESTAURANT_NAME="Tony's Tacos" PRIMARY_COLOR="#F4A261" LOGO_URL="🌮" mix phx.server
```

---

## Order Lifecycle (Oban)

When an order is created, Oban schedules automatic transitions:

```
new ──(2 min)──► preparing ──(3 min)──► out_for_delivery ──(5 min)──► delivered
```

Each transition broadcasts via PubSub so the dashboard updates in real-time without polling.

---

## Running Tests

```bash
mix test
```

Full quality gauntlet (used before every commit):

```bash
mix compile --warnings-as-errors && mix format --check-formatted && mix test
```

---

## Deployment (Fly.io)

### Initial deploy

```bash
# Install flyctl
curl -L https://fly.io/install.sh | sh

# Get token
FULL_TOKEN=$(op item get "Fly.ioOrgToken" --vault "Mr Bot" --format json | jq -r '.fields[].value')
export FLY_API_TOKEN="$FULL_TOKEN"

# Launch (creates fly.toml + Postgres)
fly launch --name restaurant-dash

# Deploy
fly deploy

# Run migrations + seeds
fly ssh console -C "/app/bin/restaurant_dash eval 'RestaurantDash.Release.migrate()'"
fly ssh console -C "/app/bin/restaurant_dash eval 'RestaurantDash.Release.seed()'"
```

### Set white-label env vars

```bash
fly secrets set RESTAURANT_NAME="Sal's Pizza" PRIMARY_COLOR="#E63946" LOGO_URL="🍕"
```

### Scale

```bash
fly scale count 2  # multiple instances, PubSub works via Fly's private network
```

---

## Architecture Notes

- **PubSub topics** — all order events broadcast on `"orders"` topic; LiveView subscribes on connect
- **Oban queues** — `orders` (lifecycle transitions), `drivers` (location simulation), `default`
- **Driver simulation** — `DriverSimulationWorker` nudges lat/lng every minute via Oban cron
- **Map hook** — `DeliveryMap` JS hook listens for `update_marker` push events from server to move markers

---

## Known Limitations & Rough Edges

- **Geocoding** — addresses are assigned random SF-area coordinates (no real geocoding)
- **Driver simulation** — simple random walk (±0.0005°), not following roads
- **No auth** — dashboard is open, suitable for internal demo only
- **Cron granularity** — Oban cron minimum is 1 minute; driver positions update every minute (not every 30s as spec'd)
- **Map markers** — refresh on PubSub events, not sub-second smooth animation
