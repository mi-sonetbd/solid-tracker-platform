# Real Add Dealer Integration

## Backend contract

The management web panel uses the existing Dealer API:

- `GET /api/v1/dealers`
- `POST /api/v1/dealers`

Backend authorization remains authoritative:

- list requires `dealer.view`;
- create requires `dealer.manage`;
- create requires platform scope;
- Dealer creation writes `dealer.created` to the immutable audit log.

## Web BFF

Browser requests use:

- `GET /api/management/dealers`
- `POST /api/management/dealers`

The BFF:

- reads HttpOnly access and refresh cookies;
- never exposes backend tokens to browser JavaScript;
- rotates an expired access token when possible;
- forwards backend validation and permission errors;
- clears cookies when the authenticated session is invalid.

## Add Dealer form

Fields:

- Dealer name
- Legal business name
- Contact mobile
- Contact email
- Trade license number
- Tax identification number
- Commission enabled

The backend generates both the Organization code and Dealer profile code.

## Role behavior

The Add Dealer control requires:

1. Super Admin or Admin management workspace;
2. `dealer.manage` permission.

Dealer and Dealer Manager workspaces cannot create another Dealer.

## Dealer directory

The Account Management page now displays real Dealer records within the
authenticated backend scope and supports:

- search;
- refresh;
- status;
- contact details;
- commission state;
- Customer count;
- staff count;
- creation date.

## Next stage

After visual and operational approval:

1. create Dealer Owner or Dealer Manager login;
2. add Customer under Platform or Dealer;
3. connect the real account hierarchy;
4. implement device import, bind, and sell/move.