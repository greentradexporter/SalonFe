"use client";

import { useEffect, useRef } from "react";

export type CustomerLocation = {
  latitude: number;
  longitude: number;
  accuracyMeters: number;
  capturedAtMillis: number;
};

type Profile = {
  name: string;
  phone: string;
  email: string;
  customerLocation?: CustomerLocation | null;
};

export function CustomerLocationDetails({ location }: { location?: CustomerLocation | null }) {
  const valid = location && Number.isFinite(location.latitude) &&
    Math.abs(location.latitude) <= 90 && Number.isFinite(location.longitude) &&
    Math.abs(location.longitude) <= 180 && Number.isFinite(location.capturedAtMillis) &&
    location.capturedAtMillis > 0 && location.capturedAtMillis < 8640000000000000;
  return <section className="customer-location-card" aria-labelledby="customer-location-title">
    <h3 id="customer-location-title">Discovery location</h3>
    {valid ? <>
      <p className="customer-location-status">Approximate location saved</p>
      <dl className="customer-location-values">
        <div><dt>Latitude</dt><dd>{location.latitude.toFixed(3)}</dd></div>
        <div><dt>Longitude</dt><dd>{location.longitude.toFixed(3)}</dd></div>
        <div className="location-wide"><dt>Last captured · India time</dt><dd><time dateTime={new Date(location.capturedAtMillis).toISOString()}>{new Intl.DateTimeFormat("en-IN", {dateStyle: "medium", timeStyle: "short", timeZone: "Asia/Kolkata"}).format(location.capturedAtMillis)}</time></dd></div>
        <div className="location-wide"><dt>Approximate accuracy</dt><dd>{Math.ceil(Math.max(100, Number.isFinite(location.accuracyMeters) ? location.accuracyMeters : 100)).toLocaleString("en-IN")} metres</dd></div>
      </dl>
      <a className="customer-location-map" href={`https://www.google.com/maps/search/?api=1&query=${location.latitude.toFixed(3)},${location.longitude.toFixed(3)}`} target="_blank" rel="noopener noreferrer" referrerPolicy="no-referrer">Open location in Maps</a>
      <p className="customer-location-note">The customer allowed this snapshot for finding salons. It may be outdated and is not a live location or a home address. Maps opens only when you choose the link.</p>
    </> : <>
      <p className="customer-location-status empty">No location saved</p>
      <p className="customer-location-note">The customer may not have allowed location, may have cleared it, or may not have used discovery while signed in.</p>
    </>}
  </section>;
}

export default function CustomerProfile({ customer, onClose }: { customer: Profile; onClose: () => void }) {
  const dialog = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const element = dialog.current;
    element?.showModal();
    return () => element?.close();
  }, []);
  return <dialog ref={dialog} className="customer-profile-dialog" aria-labelledby="customer-profile-title" onClose={onClose} onClick={(event) => event.target === event.currentTarget && onClose()}>
    <div className="customer-profile-content">
      <button className="customer-profile-close" autoFocus onClick={onClose} aria-label="Close customer profile">×</button>
      <p className="customer-profile-label">Customer profile</p>
      <h2 id="customer-profile-title">{customer.name}</h2>
      <p className="customer-profile-contact">{customer.phone || "No phone number"}{customer.email ? <><br />{customer.email}</> : null}</p>
      <CustomerLocationDetails location={customer.customerLocation} />
    </div>
  </dialog>;
}
