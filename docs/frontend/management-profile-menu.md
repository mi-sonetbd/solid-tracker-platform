# Management Profile Menu

The Admin and Dealer management header includes a right-side user menu.

## Menu actions

- Settings
- Sign out

## Behavior

- Opens from the authenticated user profile control.
- Displays the active management workspace and scope.
- Closes when Settings is selected.
- Closes when clicking outside the menu.
- Closes when Escape is pressed.
- Sign out calls the existing BFF logout route.
- The browser is redirected to `/login` after logout.

## Settings route

`/management/settings`

The settings screen is a foundation placeholder until the actual profile,
security, notification, and account-preference fields are connected.