// SPDX-License-Identifier: Apache-2.0
const assert = require("node:assert/strict");
const createUniDAV = require("../web/unidav_core.js");

(async () => {
  const core = await createUniDAV();
  const card = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nEND:VCARD\r\n";
  const validationPointer = core.ccall(
    "unidav_wasm_validate", "number", ["string"], [card]
  );
  assert.notEqual(validationPointer, 0);
  const validation = JSON.parse(core.UTF8ToString(validationPointer));
  core.ccall("unidav_wasm_free", null, ["number"], [validationPointer]);
  assert.equal(validation.valid, true);
  assert.equal(core.ccall("unidav_wasm_status", "number", [], []), 0);
  const availability = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\n" +
    "BEGIN:VAVAILABILITY\r\nUID:a\r\nDTSTAMP:20260801T120000Z\r\n" +
    "END:VAVAILABILITY\r\nEND:VCALENDAR\r\n";
  const availabilityPointer = core.ccall(
    "unidav_wasm_validate_availability", "number", ["string"], [availability]
  );
  assert.notEqual(availabilityPointer, 0);
  assert.equal(JSON.parse(core.UTF8ToString(availabilityPointer)).valid, true);
  core.ccall("unidav_wasm_free", null, ["number"], [availabilityPointer]);
  const mergePointer = core.ccall(
    "unidav_wasm_merge_three_way", "number", ["string", "string", "string"],
    [card, card.replace("FN:Ada", "FN:Grace"), card]
  );
  assert.notEqual(mergePointer, 0);
  const merge = JSON.parse(core.UTF8ToString(mergePointer));
  assert.match(merge.document, /FN:Grace/);
  assert.deepEqual(merge.conflicts, []);
  core.ccall("unidav_wasm_free", null, ["number"], [mergePointer]);

  const normalizedPointer = core.ccall(
    "unidav_wasm_normalize", "number", ["string"], [card.replaceAll("\r\n", "\n")]
  );
  assert.notEqual(normalizedPointer, 0);
  const normalized = core.UTF8ToString(normalizedPointer);
  core.ccall("unidav_wasm_free", null, ["number"], [normalizedPointer]);
  assert.equal(normalized, card);
  const projectionPointer = core.ccall(
    "unidav_wasm_project", "number", ["string"], [card]
  );
  assert.notEqual(projectionPointer, 0);
  const projection = JSON.parse(core.UTF8ToString(projectionPointer));
  core.ccall("unidav_wasm_free", null, ["number"], [projectionPointer]);
  assert.equal(projection.kind, "contact");
  assert.equal(projection.name.fullName, "Ada");
  const jsContactPointer = core.ccall(
    "unidav_wasm_to_jscontact", "number", ["string"], [card]
  );
  assert.notEqual(jsContactPointer, 0);
  const jsContactText = core.UTF8ToString(jsContactPointer);
  const jsContact = JSON.parse(jsContactText);
  assert.equal(jsContact["@type"], "Card");
  const jsCardPointer = core.ccall(
    "unidav_wasm_from_jscontact", "number", ["string"], [jsContactText]
  );
  assert.notEqual(jsCardPointer, 0);
  assert.match(core.UTF8ToString(jsCardPointer), /FN:Ada/);
  core.ccall("unidav_wasm_free", null, ["number"], [jsCardPointer]);
  core.ccall("unidav_wasm_free", null, ["number"], [jsContactPointer]);
  const patchPointer = core.ccall("unidav_wasm_patch", "number", ["string", "string"],
    [card, JSON.stringify({ name: { fullName: "Grace" }, organizations: {}, titles: {},
      emails: {}, phones: {}, notes: {} })]);
  assert.notEqual(patchPointer, 0);
  const patched = core.UTF8ToString(patchPointer);
  core.ccall("unidav_wasm_free", null, ["number"], [patchPointer]);
  assert.match(patched, /FN:Grace/);
  const jcardPointer = core.ccall(
    "unidav_wasm_to_jcard", "number", ["string"], [card]
  );
  assert.notEqual(jcardPointer, 0);
  const jcardText = core.UTF8ToString(jcardPointer);
  assert.equal(JSON.parse(jcardText)[0], "vcard");
  const restoredPointer = core.ccall(
    "unidav_wasm_from_jcard", "number", ["string"], [jcardText]
  );
  assert.notEqual(restoredPointer, 0);
  assert.match(core.UTF8ToString(restoredPointer), /FN:Ada/);
  core.ccall("unidav_wasm_free", null, ["number"], [restoredPointer]);
  core.ccall("unidav_wasm_free", null, ["number"], [jcardPointer]);
  const recurrencePointer = core.ccall(
    "unidav_wasm_expand_recurrence", "number",
    ["string", "string", "string", "string", "number"],
    ["20260803T120000Z", "FREQ=DAILY;COUNT=2", "20260803T000000Z",
      "20260810T000000Z", 10]
  );
  assert.notEqual(recurrencePointer, 0);
  assert.deepEqual(JSON.parse(core.UTF8ToString(recurrencePointer)), [
    "20260803T120000Z", "20260804T120000Z"
  ]);
  core.ccall("unidav_wasm_free", null, ["number"], [recurrencePointer]);
  const timezonePointer = core.ccall(
    "unidav_wasm_timezone_offset", "number", ["string", "string", "string"],
    ["BEGIN:VTIMEZONE\r\nTZID:Test/Zone\r\nBEGIN:STANDARD\r\n"
      + "DTSTART:20260101T000000\r\nTZOFFSETFROM:+0200\r\n"
      + "TZOFFSETTO:+0100\r\nEND:STANDARD\r\nEND:VTIMEZONE\r\n",
      "Test/Zone", "20260201T120000"]
  );
  assert.notEqual(timezonePointer, 0);
  assert.equal(JSON.parse(core.UTF8ToString(timezonePointer)).offsetSeconds, 3600);
  core.ccall("unidav_wasm_free", null, ["number"], [timezonePointer]);
  const localPointer = core.ccall(
    "unidav_wasm_expand_recurrence_local", "number",
    ["string", "string", "string", "string", "string", "string", "number"],
    ["BEGIN:VTIMEZONE\r\nTZID:Test/Zone\r\nBEGIN:STANDARD\r\n"
      + "DTSTART:20250101T000000\r\nTZOFFSETFROM:+0100\r\n"
      + "TZOFFSETTO:+0100\r\nEND:STANDARD\r\nEND:VTIMEZONE\r\n",
      "20260101T120000", "FREQ=DAILY;COUNT=2", "Test/Zone",
      "20260101T000000Z", "20260103T000000Z", 10]
  );
  assert.notEqual(localPointer, 0);
  assert.deepEqual(JSON.parse(core.UTF8ToString(localPointer)), [
    "20260101T110000Z", "20260102T110000Z"
  ]);
  core.ccall("unidav_wasm_free", null, ["number"], [localPointer]);
  console.log("wasm facade: ok");
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
