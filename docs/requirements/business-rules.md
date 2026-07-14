# Solid Tracker Core Business Rules

## Customer management

1. Customers are either `INDIVIDUAL` or `ORGANIZATION`.
2. A customer may exist without a user account.
3. A customer may be platform-managed or dealer-managed.
4. `managingDealerId = NULL` means the customer is platform-managed.
5. A customer group belongs to exactly one dealer.
6. Customer-group membership is optional.
7. A direct customer cannot belong to a dealer customer group.
8. Customer acquisition source is historical attribution and is separate from current dealer management.
9. Dealer-transfer history must be preserved.
10. Historical commissions remain with the dealer responsible at transaction time.

## Vehicle and device rules

1. A vehicle and a GPS device are separate entities.
2. One vehicle may have at most one active `PRIMARY` GPS assignment in Version 1.
3. One GPS device may have at most one active vehicle assignment.
4. Device assignment history must never be overwritten.
5. Device ownership and device custody are separate.
6. Device lifecycle state is separate from telemetry state.
7. Vehicle business status is separate from online/offline tracking status.
8. IMEI is stored as text and must be globally unique when present.
9. Traccar IDs are external-system identifiers and must not replace Solid Tracker IDs.
10. Device replacement must end the old assignment and create a new installation and assignment transactionally.

## Subscription and billing rules

1. One active vehicle may have at most one active tracking subscription in Version 1.
2. Automatic invoice generation is supported.
3. Automatic payment is enabled only when the payment provider supports secure recurring authorization.
4. Plan prices are versioned; historical invoices retain the price effective at issue time.
5. One invoice may receive multiple payments.
6. Payments and invoices are linked through payment allocations.
7. Payment success requires verified gateway confirmation.
8. Gateway events must be idempotent.
9. Financial records are append-only; corrections use reversal or adjustment entries.
10. Customer suspension, user-account status, device lifecycle, and telemetry state remain separate.

## Commission and settlement rules

1. Commission belongs to the dealer organization, not the dealer manager.
2. Commission is calculated from the applicable rule at transaction time.
3. Commission entries store calculation snapshots.
4. Commission may move through pending, earned, available, settlement-pending, settled, or reversed states.
5. Payout accounts are verified and sensitive references are encrypted or tokenized.
6. Dealer settlements group eligible commission entries.
7. Refunds create reversals instead of deleting financial history.
8. Already-settled reversals may create a negative dealer balance to be recovered from future settlements.

## Authentication and security rules

1. Mobile number is the primary unique login identity in Version 1.
2. Normal login uses mobile number and password.
3. OTP is used for verification, activation, password recovery, and high-risk actions.
4. OTP-only login is not enabled initially.
5. Passwords and refresh tokens are stored only as hashes.
6. Access tokens are short-lived.
7. Refresh tokens are rotated and session-bound.
8. User, membership, and role-assignment statuses are evaluated separately.
9. Permissions are action-based and combined with scope.
10. Sensitive actions require audit logging.