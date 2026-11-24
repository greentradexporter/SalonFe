# Customer homepage update

The customer homepage uses the supplied PNG service illustrations at a larger size
without the old inner icon frame. Mani/Pedi uses the supplied combined pedicure
artwork. Category selection, horizontal scrolling and service filtering remain.

Recommended salon cards use the existing first salon photo (or legacy logo when
there are no photos) in a much larger portrait area. Images fill that area with
BoxFit.cover. Missing/failed images show a coral storefront placeholder. Salon
names, ratings, availability, personalized savings, opening hours and barber counts
remain. Instant booking, scheduling and the salon preview keep their existing
navigation and state logic.

Service-name summaries such as Haircut Men and Haircut Women are hidden on listing
cards. The underlying service catalog and booking selection are unchanged. The
homepage location heading, hardcoded Chembur text, listing addresses, “near you”
subtitle and “area” search hint are removed. Address data, salon detail/preview
addresses and directions remain available for booking visits. No backend or
location-data changes are required.

The customer navigation remains Discover and Profile. The Partner tab in the older
reference image is not restored; the approved customer/owner separation remains.

Verification includes the existing discovery, multi-service filtering, search,
instant/schedule navigation, discounts and notification tests. A small-screen
check with larger text verifies that photos stay large, service summaries/location
stay hidden, and booking controls remain available. Preview and build artifacts
are under output/salonfe/.
