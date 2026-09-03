# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import unidav


def test_version():
    # The version's copies are checked against each other in
    # tests/test_version.nim; this is the one that reads it through the
    # extension, which is the only place a wheel can be wrong on its own.
    assert unidav.version() == "0.1.0"


def test_validate_vcard():
    result = unidav.validate("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nEND:VCARD\r\n")
    assert result["valid"] is True

def test_validate_availability():
    value = ("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\n"
             "BEGIN:VAVAILABILITY\r\nUID:a\r\nDTSTAMP:20260801T120000Z\r\n"
             "END:VAVAILABILITY\r\nEND:VCALENDAR\r\n")
    assert unidav.validate_availability(value) is True

def test_three_way_merge():
    base = "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:a\r\nFN:Ada\r\nEND:VCARD\r\n"
    local = base.replace("FN:Ada", "FN:Grace")
    outcome = unidav.merge(base, local, base)
    assert "FN:Grace" in outcome["document"]
    assert outcome["conflicts"] == []

def test_normalize_vcard():
    value = unidav.normalize("begin:vcard\nversion:4.0\nfn:Ada\nend:vcard\n")
    assert value == "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nEND:VCARD\r\n"

def test_normalize_rejects_invalid_syntax():
    import pytest
    with pytest.raises(ValueError):
        unidav.normalize("BROKEN")

def test_project_vcard():
    value = unidav.project("BEGIN:VCARD\r\nVERSION:4.0\r\nUID:urn:uuid:ada\r\nFN:Ada\r\nEND:VCARD\r\n")
    assert value["kind"] == "contact"
    assert value["uid"] == "urn:uuid:ada"
    patched = unidav.patch("BEGIN:VCARD\r\nVERSION:4.0\r\nUID:urn:uuid:ada\r\nFN:Ada\r\nEND:VCARD\r\n",
        {"name": {"fullName": "Grace"}, "organizations": {}, "titles": {},
         "emails": {}, "phones": {}, "notes": {}})
    assert "FN:Grace" in patched

def test_jcard_and_jcal_round_trips():
    card = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nEND:VCARD\r\n"
    jcard = unidav.to_jcard(card)
    assert jcard[0] == "vcard"
    assert "FN:Ada" in unidav.from_jcard(jcard)
    calendar = ("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\n"
                "BEGIN:VEVENT\r\nUID:1\r\nDTSTAMP:20260801T120000Z\r\n"
                "END:VEVENT\r\nEND:VCALENDAR\r\n")
    jcal = unidav.to_jcal(calendar)
    assert jcal[0] == "vcalendar"
    assert "BEGIN:VEVENT" in unidav.from_jcal(jcal)

def test_jscontact_round_trip_preserves_vcard_props():
    card = ("BEGIN:VCARD\r\nVERSION:4.0\r\nUID:urn:uuid:ada\r\n"
            "FN:Ada\r\nX-EXAMPLE:kept\r\nEND:VCARD\r\n")
    contact = unidav.to_jscontact(card)
    assert contact["version"] == "2.0"
    assert contact["vCardProps"][0][0] == "x-example"
    restored = unidav.from_jscontact(contact)
    assert "X-EXAMPLE:kept" in restored


def test_bounded_recurrence():
    assert unidav.expand_recurrence(
        "20260803T120000Z", "FREQ=DAILY;COUNT=2",
        "20260803T000000Z", "20260810T000000Z") == [
            "20260803T120000Z", "20260804T120000Z"]


def test_vtimezone_offset():
    timezone = ("BEGIN:VTIMEZONE\r\nTZID:Test/Zone\r\n"
                "BEGIN:STANDARD\r\nDTSTART:20260101T000000\r\n"
                "TZOFFSETFROM:+0200\r\nTZOFFSETTO:+0100\r\n"
                "END:STANDARD\r\nEND:VTIMEZONE\r\n")
    assert unidav.timezone_offset(timezone, "Test/Zone", "20260201T120000") == 3600

def test_local_recurrence():
    timezone = ("BEGIN:VTIMEZONE\r\nTZID:Test/Zone\r\n"
                "BEGIN:STANDARD\r\nDTSTART:20250101T000000\r\n"
                "TZOFFSETFROM:+0100\r\nTZOFFSETTO:+0100\r\n"
                "END:STANDARD\r\nEND:VTIMEZONE\r\n")
    assert unidav.expand_recurrence_local(
        timezone, "20260101T120000", "FREQ=DAILY;COUNT=2", "Test/Zone",
        "20260101T000000Z", "20260103T000000Z") == [
            "20260101T110000Z", "20260102T110000Z"]
    assert unidav.status() == 0
