# Local Traccar Bootstrap

The Solid Tracker Traccar bootstrap script configures the local Traccar
integration through authenticated Solid Tracker APIs.

## Purpose

The script performs these operations:

1. Authenticates as a Solid Tracker platform administrator.
2. Creates or updates the local Traccar server configuration.
3. Marks the selected Traccar server as active and default.
4. Securely replaces the stored Traccar credentials.
5. Runs a Traccar API health check.
6. Optionally synchronizes installed devices missing an active mapping.
7. Skips devices that already have an active synchronized mapping.

The script does not modify Traccar integration tables directly.

## Prerequisites

The following services must be running:

- Solid Tracker backend API
- PostgreSQL
- Redis
- Traccar

Default local endpoints:

- Solid Tracker API: `http://127.0.0.1:3000/api/v1`
- Traccar API: `http://127.0.0.1:8082`
- Traccar OsmAnd receiver: `http://127.0.0.1:5055`

The Solid Tracker administrator must have the `device.register` permission.

## Configure the default Traccar server

Run from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\solid-tracker-bootstrap-traccar.ps1" -AdminMobileNumber "01937342993" -TraccarUsername "imsonet.bd@gmail.com"
```

The script securely prompts for:

- Solid Tracker administrator password
- Traccar password

Passwords are not accepted as command-line parameters.

## Backfill installed devices

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\solid-tracker-bootstrap-traccar.ps1" -AdminMobileNumber "01937342993" -TraccarUsername "imsonet.bd@gmail.com" -BackfillInstalledDevices
```

Installed devices with an active `SYNCED` mapping are skipped.

Devices without an active mapping are synchronized with the selected default
Traccar server.

## Force resynchronization

Use force synchronization when the Traccar database was recreated or a stored
mapping may be stale:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\solid-tracker-bootstrap-traccar.ps1" -AdminMobileNumber "01937342993" -TraccarUsername "imsonet.bd@gmail.com" -BackfillInstalledDevices -ForceResync
```

## Expected result

A successful run confirms:

- Traccar server status is `ACTIVE`.
- The server is marked as default.
- Credentials are configured.
- Traccar health status is `UP`.
- Missing installed-device mappings are created.
- Existing valid mappings are preserved.
- Future installations can use the default Traccar server automatically.

## Security

- Passwords are entered through secure PowerShell prompts.
- Passwords are not stored in command history.
- Traccar credentials are submitted to the authenticated Solid Tracker API.
- Solid Tracker stores the credential through its encrypted credential service.