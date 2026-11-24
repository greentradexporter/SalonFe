# Customer discovery location in SalonFe Control

Published and verified on 25 November 2026.

Open https://pritze-control-center.greentradexporter.chatgpt.site/ and choose
Customers, then Profile beside the customer. The read-only profile displays the
latest saved approximate discovery latitude/longitude, capture time in India,
accuracy and an optional Maps link. It explicitly identifies the value as a
snapshot that may be outdated, rather than a live position or home address.
No map, geocoder or third-party request runs automatically.

The existing mobile app writes `users/{uid}.customerLocation` only after the
customer allows discovery location and is signed in. Coordinates are rounded to
three decimal places, accuracy is at least 100 metres, purpose is
`salon_discovery`, and `capturedAt` is a server timestamp. Clearing discovery
location removes the field. Guest locations are not attached to user profiles.
Customers without a valid saved snapshot see “No location saved.” Existing users
must use the location feature while signed in before data can appear here.

`getAdminPhaseOneData` now projects only those four display fields through
`adminCustomerRecord`. The projection rejects missing coordinates, wrong
purposes, invalid timestamps and invalid ranges. It does not expose arrival
tracking records, add location to audit snapshots or enable administrators to
edit location. Existing administrator authentication and Firestore rules remain
in force. Profile data refreshes with the dashboard's existing 30-second refresh.

Deployment updated only the archived source of the existing Mumbai admin data
endpoint. CPU, memory, min/max instance caps, concurrency, timeout, identity,
environment/secret references and IAM were verified unchanged; startup/scaling
safeguards were preserved. An unsigned request returns HTTP 401.

Site version: 29. Source commit:
`7053c05224a324c79e7b85b735d5e25230967665`.
Canonical source: `admin-site-cleanup/.sites-checkout`; GitHub mirror: `admin/`.
The existing Site audience and app-level administrator restrictions are retained.

Validation: production build, 15 website tests, seven backend location/security
checks, local browser checks for saved/empty snapshots and Escape dismissal, and
live Chrome verification of Customers → Profile using the dedicated review
account. Synthetic preview and deployment proof are retained locally under the
ignored `output/admin-customer-location/` directory. No real customer location was
created or changed for verification, and no mobile-store update is required.
