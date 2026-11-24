# SalonFe owner screens

Home replaces Overview. Its two totals are completed-booking total earnings and
completed-booking earnings for today. Top services ranks the existing captured
service revenue. The bottom View bookings button opens Bookings. Existing salon
approval, setup and instant-booking controls remain operational.

Bookings groups requests under Needs Action, confirmed/started bookings under
Live Bookings, and completed/cancelled/rejected/expired bookings under the collapsed
Previous bookings control. The four-stage timeline is Booked, Accepted, Started,
Done. Accept, Reject, Start Service and Complete Service call the existing booking
workflow. Cancellation, visit rating, extra services and arrival information remain
in Booking details. Booking notifications open Bookings and expand history when
needed. The duplicate owner floating booking footer is removed.

Shop replaces Team and embeds the editable registration form. Owner email and the
header pencil are removed. Photos and barbers precede the save button. Existing
barbers keep their editable staff profiles; new registrations can stage named
barbers before the first save. Payout settings and the existing service editor
remain in Shop.

Photo uploads are staged in Storage without creating/updating a salon profile.
Photo removal is staged in the form. Save validates at least one photo and one
active named barber on the client and in the new owner-only saveOwnerSalonShop
callable. The server transaction saves the profile and any initial barbers together,
preserves existing approval status, checks every barber ID and accepts phone-only
owners without requiring email. The legacy profile/photo APIs stay compatible with
previous installed builds. Leaving an unsaved form can leave unreferenced uploaded
images in Storage; it does not publish an incomplete salon.

The account menu replaces Revenue details, Promotional credits and Phone login
with Balance. Existing login credentials and backend coupon/credit functionality
are retained. Balance shows only Deposit amount, Discount, Balance and SalonFe
earning, loaded by the owner-only getSalonBalanceSummary callable. Loading failures
show retry, never a fabricated zero balance.

## Balance definition

Amounts are INR (the existing Proin conversion is 1:1):

- Deposit: originalProin across this salon's salon_promotion_credits lots marked
  salonDeposit=true. Complimentary grants, customer reward lots and credit limits
  are excluded.
- Discount: discountAmount across completed salon bookings.
- SalonFe earning: max(0, pritzePayoutAmount - discountAmount) per completed booking.
  Payout already contains the discount reimbursement, so only its extra amount is
  counted here. Customer Proin redemption/reimbursement is separate.
- Balance: deposit - discount - earning. Negative balances remain visible.

Example: deposit 1,000, customer discount 10, total payout 20 => Discount 10,
SalonFe earning 10, Balance 980. Both collections are read through all pages;
reserved, rejected and cancelled bookings do not reduce this display. This screen
is a summary, and does not change wallet balances, credit limits or settlements.

## Delivery and verification

Only the two new callables were deployed to trimtime-46539 in asia-south1. No
production records were changed to test them. Old notification/email branding
changes in other functions are outside this deployment.

The owner update is in output/salonfe/SalonFe-owner-1.0.28-58.apk. Package ID,
Firebase configuration and signing identity are preserved. Install this APK to see
the UI changes; existing installations do not change just because the backend was
deployed. iOS has an unsigned device compilation and requires normal signing and
store distribution. Nothing was submitted to Google Play or the App Store.

Validation logs and previews are in output/. Automated coverage includes required
photo/barber checks, phone-only registration, edit persistence, owner authorization,
atomic initial barber creation, inactive/foreign barber rejection, pagination over
501 deposits, balance arithmetic, booking actions, history disclosure and retry.
