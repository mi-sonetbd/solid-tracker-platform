# Traccar production integration

The production stack uses the official `traccar/traccar:6.14.5-alpine` image.

Configuration is supplied through environment variables with
`CONFIG_USE_ENVIRONMENT_VARIABLES=true`. This keeps database and webhook
secrets out of tracked XML files.

The Traccar web/API port is bound only to `127.0.0.1` on the Droplet. Solid
Tracker reaches it over the private Compose network at `http://traccar:8082`.

Only the exact device protocol port should be exposed publicly. The example
uses GT06 port `5023`; replace both `TRACCAR_DEVICE_PROTOCOL` and
`TRACCAR_DEVICE_PORT` after confirming the physical tracker model.

Event forwarding targets:

`http://backend-api:3000/api/v1/tracking/webhooks/traccar/{serverCode}`

The forwarding request includes `X-Tracking-Webhook-Secret`.
