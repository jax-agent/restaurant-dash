# RestaurantDash — Full Product Plan

## Vision
White-label restaurant delivery SaaS for small businesses. One deploy, many restaurants.
Competes with ChowNow/Olo but built on modern Elixir/Phoenix with real-time everything.

## Architecture

### Multi-Tenancy
- PostgreSQL Row-Level Security (RLS) per restaurant tenant
- Tenant resolution via subdomain (sals-pizza.restaurantdash.fly.dev) or custom domain
- Shared DB for small restaurants, option for dedicated DB for enterprise

### Stack
- **Backend:** Elixir/Phoenix 1.8, LiveView, Ecto, Oban
- **DB:** PostgreSQL + PostGIS (delivery zones, driver tracking)
- **Real-time:** Phoenix PubSub + Channels (already built-in)
- **Payments:** Stripe Connect (marketplace model — we collect, restaurants get paid)
- **POS:** Clover REST API, Square API (Catalog + Orders + Payments)
- **Delivery:** DoorDash Drive API, own-fleet with driver app
- **Maps:** Leaflet + OpenStreetMap (free), Google Maps API for geocoding
- **SMS:** Twilio (order notifications)
- **Email:** SendGrid or Resend (receipts, confirmations)
- **Auth:** `phx.gen.auth` + role-based (owner, staff, driver, customer)
- **Deploy:** Fly.io (multi-region)

---

## Phases (Vertical Slices)

### Phase 1: Multi-Tenant Foundation + Auth ← START HERE
**Goal:** Multiple restaurants can sign up, each gets their own branded space

Slices:
1. **Tenant schema + RLS** — `restaurants` table, `restaurant_id` on all tables, RLS policies
2. **Auth system** — `phx.gen.auth`, roles (owner, staff, driver, customer), scoped to restaurant
3. **Restaurant onboarding** — signup flow creates restaurant + owner account
4. **Subdomain routing** — `sals-pizza.restaurantdash.fly.dev` resolves to correct tenant
5. **White-label settings** — per-restaurant: name, colors, logo, hours, address, phone

### Phase 2: Menu Management
**Goal:** Restaurant owners can build their menu

Slices:
1. **Menu schema** — categories, items, modifiers, modifier_groups, prices
2. **Menu CRUD** — owner dashboard to manage menu (drag-drop ordering)
3. **Modifier system** — "Size" (S/M/L), "Toppings" (+$1.50 each), "Special Instructions"
4. **Item availability** — 86 items (mark out of stock), auto-restore on schedule
5. **Menu display** — public-facing menu page for customers

### Phase 3: Customer Ordering
**Goal:** Customers can browse menu and place orders

Slices:
1. **Customer-facing menu** — browse categories, view items with photos/descriptions
2. **Cart system** — add items with modifiers, adjust quantities, see running total
3. **Checkout flow** — delivery address, phone, special instructions, order summary
4. **Guest checkout** — no account required (email + phone only)
5. **Order confirmation** — success page with order number, estimated time

### Phase 4: Payment Integration (Stripe Connect)
**Goal:** Customers pay online, restaurants get paid

Slices:
1. **Stripe Connect setup** — marketplace model, restaurant onboarding to Stripe
2. **Checkout with Stripe** — Stripe Elements in checkout, create PaymentIntent
3. **Order payment flow** — authorize on order → capture on delivery
4. **Tip handling** — customer tip split (100% to driver)
5. **Restaurant payouts** — Stripe Connect auto-payouts to restaurant bank account
6. **Refund system** — owner/admin can refund orders

### Phase 5: Kitchen & Operations
**Goal:** Kitchen staff can manage incoming orders efficiently

Slices:
1. **Kitchen Display System (KDS)** — big-screen view, new orders flash, timers
2. **Order queue management** — accept/reject orders, mark items as cooking/done
3. **Prep time estimation** — based on items + current queue depth
4. **Printer integration** — ESC/POS thermal printer support (Star Micronics, Epson)
5. **Audio alerts** — new order sound, overdue order escalation

### Phase 6: Driver Management & Delivery
**Goal:** Assign drivers and track deliveries in real-time

Slices:
1. **Driver accounts** — driver role, availability toggle, shift scheduling
2. **Driver assignment** — manual assign or auto-dispatch (nearest available)
3. **Driver mobile view** — mobile-optimized: pending deliveries, navigation, status updates
4. **Real-time GPS tracking** — driver reports location, customer sees live map
5. **Delivery status flow** — assigned → picked up → en route → delivered
6. **Proof of delivery** — photo capture on delivery
7. **Driver earnings** — track per-delivery pay + tips

### Phase 7: DoorDash Drive Integration
**Goal:** Use DoorDash's driver network as overflow/default delivery

Slices:
1. **DoorDash Drive client** — JWT auth, sandbox setup
2. **Delivery quotes** — get price/ETA before customer checks out
3. **Create deliveries** — push accepted orders to DoorDash
4. **Webhook handler** — track Dasher assignment, pickup, delivery
5. **Fallback logic** — own fleet first → DoorDash if no driver available

### Phase 8: POS Integration — Clover
**Goal:** Sync with Clover POS (menu, orders, payments)

Slices:
1. **Clover OAuth** — restaurant connects their Clover account
2. **Menu import** — pull catalog from Clover → populate menu
3. **Order push** — send online orders to Clover POS/KDS
4. **Inventory sync** — 86'd items sync from Clover → menu
5. **Payment reconciliation** — match online payments with Clover reporting

### Phase 9: POS Integration — Square
**Goal:** Same as Clover but for Square merchants

Slices:
1. **Square OAuth** — connect Square account
2. **Catalog sync** — import menu from Square Catalog API
3. **Order sync** — push orders to Square POS
4. **Square Payments** — option to use Square instead of Stripe for payment
5. **Webhook handler** — real-time sync of order/inventory changes

### Phase 10: Notifications & Communication
**Goal:** Keep customers informed throughout the order lifecycle

Slices:
1. **SMS via Twilio** — order confirmed, out for delivery, delivered
2. **Email receipts** — order confirmation + digital receipt via SendGrid
3. **Push notifications** — web push for driver app
4. **Customer order tracking page** — real-time status + map (public, no login needed)
5. **Restaurant alerts** — new order alerts, driver issues, payment problems

### Phase 11: Analytics & Reporting
**Goal:** Restaurant owners can see how their business is doing

Slices:
1. **Dashboard overview** — today's orders, revenue, avg delivery time
2. **Sales reports** — daily/weekly/monthly, by item, by category
3. **Popular items** — top sellers, trending items
4. **Delivery metrics** — avg time, driver performance, zones
5. **Customer insights** — repeat customers, avg order value, retention

### Phase 12: Advanced Features
**Goal:** Competitive feature parity with established platforms

Slices:
1. **Promo codes & discounts** — percentage/fixed, per-item/order, expiration
2. **Loyalty program** — points per dollar, rewards redemption
3. **Delivery zones & fees** — polygon-based zones, distance-based pricing
4. **Scheduled orders** — order now, deliver later
5. **Customer reviews & ratings** — per-order rating, driver rating
6. **Multi-location support** — one restaurant brand, multiple physical locations

---

## Execution Plan

### Parallel Tracks
We can run up to 3-4 sub-agents in parallel on independent slices:

**Track A:** Multi-tenant + Auth (Phase 1)
**Track B:** Menu Management (Phase 2) — depends on Phase 1 tenant schema
**Track C:** Customer Ordering (Phase 3) — depends on Phase 2 menu

So phases 1→2→3 are sequential, but within each phase slices can parallelize.
After Phase 3 is done, Phases 4-10 can largely parallelize.

### Today's Priority
1. Phase 1: Multi-tenant + Auth (foundation for everything)
2. Phase 2: Menu Management (restaurant owners need this first)
