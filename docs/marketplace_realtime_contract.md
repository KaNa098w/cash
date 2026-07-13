# Marketplace Orders Realtime Contract

Desktop POS gets marketplace realtime settings from the POS endpoint.

```http
GET /api/organizations/pos/{pos_key}?device_id={device_id}
```

Expected response fragment:

```json
{
  "data": {
    "id": "...",
    "key": "...",
    "device_id": "DESKTOP-DEVICE-001",
    "store_id": "...",
    "marketplace_orders_channel": "pos.store.{store_id}.marketplace.orders",
    "realtime": {
      "enabled": true,
      "driver": "reverb",
      "protocol": "wss",
      "host": "api.example.com",
      "port": 443,
      "path": "/app/{key}",
      "app_key": "reverb-public-key",
      "channel": "pos.store.{store_id}.marketplace.orders",
      "event": "marketplace.order.created"
    }
  }
}
```

## Channel

Current desktop implementation expects a public channel and subscribes without a channel authorization endpoint.

If backend moves this to `PrivateChannel` or `PresenceChannel`, backend must also provide a POS-safe authorization endpoint and request contract. Until that exists, desktop will keep polling as fallback.

## Event

Backend event:

```php
App\Events\MarketplaceOrderCreatedForPos
```

Broadcast event name:

```text
marketplace.order.created
```

Payload:

```json
{
  "type": "marketplace_order_created",
  "orderId": "...",
  "organizationId": "...",
  "warehouseId": "...",
  "storeId": "..."
}
```

Desktop POS must not treat this payload as a full order. It only triggers:

```http
GET /api/organizations/pos/{pos_key}/marketplace/orders?device_id={device_id}&scope=new&take=20
```

## Fallback Polling

Desktop POS keeps polling even when WebSocket is connected.

```text
interval: 25 seconds
scope: new
take: 20
```
