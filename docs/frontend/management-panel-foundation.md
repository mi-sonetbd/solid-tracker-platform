# Solid Tracker Management Panel Foundation

## UI decision

The approved Customer interface remains isolated as `CustomerShell`.

The new management interface follows the supplied reference architecture while
retaining the existing Solid Tracker light palette, typography, spacing, and
branding.

## Supported workspaces

- Super Admin
- Admin
- Dealer Manager
- Dealer

These workspaces route to `/management/monitor`.

## Management routes

- `/management/monitor`
- `/management/report`
- `/management/device`
- `/management/accounts`
- `/management/video`
- `/management/fleet`

## Foundation components

- `ManagementShell`
- `AccountTree`
- `ManagementRail`
- `ManagedDeviceList`
- `DeviceManagementWorkspace`
- `SellMoveModal`

## Role behavior

- Super Admin and Admin may manage Dealers and Customers.
- Dealer Manager and Dealer may manage Customers within their scope.
- Customer accounts remain restricted to the Customer workspace.
- Unknown roles remain on the template-pending route.

## Current stage

This commit establishes the visual and routing foundation only. Buttons and
tables intentionally use representative data.

## Next stage

1. connect the account hierarchy to real organizations, dealers, and customers;
2. implement create Dealer;
3. implement create Customer and login membership;
4. implement device import/bind;
5. implement sell/move device transfer;
6. enforce permission and scope checks in every mutation;
7. connect management device status and live tracking.