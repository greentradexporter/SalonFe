import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";
import ts from "typescript";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";

const source = fs.readFileSync(new URL("../app/CustomerProfile.tsx", import.meta.url), "utf8");
const compiled = new URL("../.wrangler/customer-profile-test.mjs", import.meta.url);
fs.mkdirSync(new URL("../.wrangler/", import.meta.url), {recursive: true});
fs.writeFileSync(compiled, ts.transpileModule(source, {compilerOptions: {
  jsx: ts.JsxEmit.ReactJSX, module: ts.ModuleKind.ESNext,
}}).outputText);
const {CustomerLocationDetails} = await import(compiled.href);
const render = (location) => renderToStaticMarkup(React.createElement(CustomerLocationDetails, {location}));
const location = {latitude: 19.052, longitude: 72.9, accuracyMeters: 12,
  capturedAtMillis: Date.UTC(2026, 10, 24, 10)};

test("profile renders approximate coordinates, India capture time and an opt-in map link", () => {
  const html = render(location);
  assert.match(html, /19\.052/);
  assert.match(html, /72\.900/);
  assert.match(html, /100.*metres/);
  assert.match(html, /India time/);
  assert.match(html, /15:30|3:30/);
  assert.match(html, /href="https:\/\/www.google.com\/maps\/search\/\?api=1/);
  assert.match(html, /not a live location/);
  assert.doesNotMatch(html, /<iframe|<img/);
});

test("cleared or invalid snapshots show no map or misleading coordinates", () => {
  for (const value of [null, undefined, {...location, latitude: null},
    {...location, longitude: NaN}, {...location, latitude: 100},
    {...location, capturedAtMillis: 0}]) {
    const html = render(value);
    assert.match(html, /No location saved/);
    assert.doesNotMatch(html, /<a|19\.052/);
  }
});
