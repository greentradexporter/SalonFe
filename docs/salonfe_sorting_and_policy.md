# Salon sorting and policy contact update

The customer listing heading has a Sort button opening a compact selection sheet:

- Recommended prioritizes matching salon names/services and currently open, bookable salons, followed by rating and review count.
- Nearest uses approximate straight-line distance from the customer's consented discovery location to the salon's map pin. It calculates distances on the device, without a new cloud function or Maps API call per customer. Location is requested only when needed, with a loading indicator and a Recommended fallback when unavailable.
- Highest rated orders by stars, then review count. Existing search and service filters apply before every sort.

Salons without usable map pins remain visible after located salons. Pins come from validated public latitude/longitude fields or a coordinate-bearing Maps destination URL. A Maps viewport is not treated as a salon pin. Source-derived pins are invalidated if the salon changes its directions link. Coordinate fields survive the existing owner cache round trip.

On 24 November 2026, the existing public map links for 11 approved salons were resolved to destination pins and saved with update-time preconditions. Other salon fields were preserved. The remaining approved listing, Cutting place, links to Chembur railway station, so its location was left unverified. Private audit records are in ignored output/salon-sorting/.

The original detailed service illustrations are restored throughout the app. Existing Haircut, Beard, Spa, Mani/Pedi, Threading, Waxing and other artwork remains. Facial and Makeup use distinct matching 3D assets instead of sharing the Spa image. The two replacement images were generated with the built-in image tool using the original artwork as style references: white, charcoal and coral 3D facial-mask/application-brush artwork; and compact, lipstick and makeup-brush artwork. Assets are assets/service_icons/facial-v2.png and makeup-v2.png.

In-app, public HTML and repository Markdown policies contain the support phone number +91 89996 08278, without a personal operator name or email. The policy generator updates all copies together. Website footers use the phone contact as well. Public Hosting was deployed and verified; the app changes require a subsequent Android/iOS release.

Validation: focused sorting, discovery and owner regression tests; existing customer workflow regression tests; Flutter analysis; public policy response checks; map-pin write verification; and a rendered mobile sorting-sheet preview. Exact run logs and previews are in ignored output/ or /tmp/.
