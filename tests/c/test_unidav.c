/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 lituus-lab */
/* Every check here is an assert, so NDEBUG would turn this file into an empty
   program that reports success. Undefined before the header that reads it. */
#undef NDEBUG
#include <assert.h>
#include <string.h>
#include "UniDAV.h"

int main(void) {
  assert(strcmp(unidav_version(), "0.1.0") == 0);
  assert(unidav_status() == 0);
  char *result = unidav_validate_json("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nEND:VCARD\r\n");
  assert(result != NULL);
  assert(strstr(result, "\"valid\":true") != NULL);
  unidav_free(result);
  char *normalized = unidav_normalize("begin:vcard\nversion:4.0\nfn:Ada\nend:vcard\n");
  assert(normalized != NULL);
  assert(strcmp(normalized, "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nEND:VCARD\r\n") == 0);
  unidav_free(normalized);
  char *projection = unidav_project_json("BEGIN:VCARD\r\nVERSION:4.0\r\nUID:urn:uuid:ada\r\nFN:Ada\r\nEND:VCARD\r\n");
  assert(projection != NULL);
  assert(strstr(projection, "\"kind\":\"contact\"") != NULL);
  unidav_free(projection);
  char *availability = unidav_validate_availability(
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\n"
    "BEGIN:VAVAILABILITY\r\nUID:a\r\nDTSTAMP:20260801T120000Z\r\n"
    "END:VAVAILABILITY\r\nEND:VCALENDAR\r\n");
  assert(availability != NULL);
  assert(strstr(availability, "\"valid\":true") != NULL);
  unidav_free(availability);
  char *merged = unidav_merge_three_way(
    "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:urn:uuid:a\r\nFN:Ada\r\nEND:VCARD\r\n",
    "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:urn:uuid:a\r\nFN:Grace\r\nEND:VCARD\r\n",
    "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:urn:uuid:a\r\nFN:Ada\r\nEND:VCARD\r\n");
  assert(merged != NULL);
  assert(strstr(merged, "FN:Grace") != NULL);
  assert(strstr(merged, "\"conflicts\":[]") != NULL);
  unidav_free(merged);
  char *patched = unidav_patch_projection(
    "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:urn:uuid:ada\r\nFN:Ada\r\nEND:VCARD\r\n",
    "{\"name\":{\"fullName\":\"Grace\"},\"organizations\":{},\"titles\":{},\"emails\":{},\"phones\":{},\"notes\":{}}");
  assert(patched != NULL);
  assert(strstr(patched, "FN:Grace") != NULL);
  unidav_free(patched);
  char *jcard = unidav_to_jcard("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nEND:VCARD\r\n");
  assert(jcard != NULL);
  assert(strstr(jcard, "[\"vcard\"") != NULL);
  char *restored_card = unidav_from_jcard(jcard);
  assert(restored_card != NULL);
  assert(strstr(restored_card, "FN:Ada") != NULL);
  unidav_free(restored_card);
  unidav_free(jcard);
  char *jcal = unidav_to_jcal("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\nBEGIN:VEVENT\r\nUID:1\r\nDTSTAMP:20260801T120000Z\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n");
  assert(jcal != NULL);
  char *restored_cal = unidav_from_jcal(jcal);
  assert(restored_cal != NULL);
  assert(strstr(restored_cal, "BEGIN:VEVENT") != NULL);
  unidav_free(restored_cal);
  unidav_free(jcal);
  char *jscontact = unidav_to_jscontact(
    "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:urn:uuid:ada\r\nFN:Ada\r\n"
    "X-EXAMPLE:kept\r\nEND:VCARD\r\n");
  assert(jscontact != NULL);
  assert(strstr(jscontact, "\"version\":\"2.0\"") != NULL);
  assert(strstr(jscontact, "x-example") != NULL);
  char *restored_jscontact = unidav_from_jscontact(jscontact);
  assert(restored_jscontact != NULL);
  assert(strstr(restored_jscontact, "X-EXAMPLE:kept") != NULL);
  unidav_free(restored_jscontact);
  unidav_free(jscontact);
  char *occurrences = unidav_expand_recurrence(
    "20260803T120000Z", "FREQ=DAILY;COUNT=2", "20260803T000000Z",
    "20260810T000000Z", 10);
  assert(occurrences != NULL);
  assert(strstr(occurrences, "20260804T120000Z") != NULL);
  unidav_free(occurrences);
  const char *timezone = "BEGIN:VTIMEZONE\r\nTZID:Test/Zone\r\n"
    "BEGIN:STANDARD\r\nDTSTART:20260101T000000\r\n"
    "TZOFFSETFROM:+0200\r\nTZOFFSETTO:+0100\r\nEND:STANDARD\r\n"
    "END:VTIMEZONE\r\n";
  char *offset = unidav_timezone_offset(timezone, "Test/Zone", "20260201T120000");
  assert(offset != NULL);
  assert(strstr(offset, "3600") != NULL);
  unidav_free(offset);
  char *local = unidav_expand_recurrence_local(timezone, "20260101T120000",
    "FREQ=DAILY;COUNT=2", "Test/Zone", "20260101T000000Z",
    "20260103T000000Z", 10);
  assert(local != NULL);
  assert(strstr(local, "20260101T110000Z") != NULL);
  unidav_free(local);
  assert(unidav_from_jcard("{}") == NULL);
  assert(unidav_status() == 2);
  assert(unidav_normalize("BROKEN") == NULL);
  return 0;
}
