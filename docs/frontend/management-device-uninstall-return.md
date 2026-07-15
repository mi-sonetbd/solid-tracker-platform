# Management Device Uninstall and Return

## Route

```text
/management/device
```

## Permission

The workflow uses the existing backend permission:

```text
device.remove
```

The web page receives this permission through the existing
`canTransferDevices` server-derived property. Backend authorization remains the
final authority.

## Installed Device

An installed Device exposes `Uninstall` in the row Actions column and through
the toolbar when exactly one eligible Device is selected.

The modal records:

- assignment end reason;
- Device removal reason;
- operational notes;
- optional Dealer-to-Platform return after uninstall.

Backend operation:

```text
POST /api/v1/devices/:deviceId/remove
```

The operation closes the active vehicle assignment and installation while
preserving immutable history.

## Dealer stock return

An uninstalled Device with an active Dealer allocation exposes `Return`.

Backend operation:

```text
POST /api/v1/devices/:deviceId/return
```

The backend rejects this operation while an active vehicle assignment exists.

## Two-step uninstall and return

For a Dealer-managed installed Device:

```text
Uninstall
    â†“
Device restored to Dealer stock
    â†“
Optional Return
    â†“
Device restored to Platform stock
```

The frontend never pretends these two mutations are atomic. If uninstall
succeeds but the following Platform return fails, the UI reports the partial
result and refreshes authoritative Device state.

## Sell/move boundary

Installed Devices continue to reject Sell/move. After a successful uninstall,
the Device can be moved from its restored stock scope.