# SPDX-License-Identifier: Apache-2.0
import std/[json, strutils, unittest]
import UniDAV

suite "UniDAV formats":
  test "validates a vCard":
    let card = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada Lovelace\r\nEND:VCARD\r\n"
    check isValid(card)
    check detectKind(card) == dkVCard

  test "validates an iCalendar":
    let calendar = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//UniDAV Tests//EN\r\nBEGIN:VEVENT\r\nUID:1\r\nDTSTAMP:20260801T120000Z\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
    check isValid(calendar)
    check detectKind(calendar) == dkICalendar
    let longCalendar = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\n" &
      "X-ONE:1\r\nX-TWO:2\r\nX-THREE:3\r\nX-FOUR:4\r\nX-FIVE:5\r\n" &
      "BEGIN:VTODO\r\nUID:task\r\nDTSTAMP:20260801T120000Z\r\nSUMMARY:Ship\r\nEND:VTODO\r\nEND:VCALENDAR\r\n"
    check isValid(longCalendar)
    check detectKind(longCalendar) == dkICalendar

  test "rejects mismatched components":
    check not isValid("BEGIN:VCARD\r\nEND:VCALENDAR\r\n")

  test "unfolds continuations":
    check unfold("NOTE:hello\r\n world\r\n") == @["NOTE:helloworld"]

  test "folding preserves UTF-8 bytes":
    let value = "NOTE:" & repeat("é", 50)
    check foldLine(value).replace("\r\n ", "") == value

  test "parses groups, quoted parameters and values containing colons":
    let line = parseContentLine("ITEM1.EMAIL;TYPE=work,internet;LABEL=\"Main office\":ada@example.test:443")
    check line.group == "ITEM1"
    check line.name == "EMAIL"
    check line.params.len == 2
    check line.params[0].values == @["work", "internet"]
    check line.params[1].values == @["Main office"]
    check line.value == "ada@example.test:443"
    let quoted = parseContentLine("EMAIL;LABEL=\"Main, office^nFloor 2\":ada@example.test")
    check quoted.params[0].values == @["Main, office\nFloor 2"]
    check parseContentLine(serializeContentLine(quoted)).params[0].values ==
        quoted.params[0].values

  test "rejects malformed and excessive content":
    expect ParseError: discard parseContentLine("BROKEN")
    expect ParseError: discard parseContentLine(":value")
    expect ParseError: discard parseContentLine("FN;TYPE:value")
    expect ParseError: discard unfold(" continuation")
    expect ParseError: discard unfold("12345", maxBytes = 4)
    expect ParseError: discard unfold("A:1\r\nB:2", maxLines = 0)
    expect ParseError: discard parseContentLine("EMAIL;LABEL=\"unterminated:value")
    check parseContentLine("EMAIL;LABEL=caret^^unknown^xquote^':a@b.test").params[
        0].values ==
      @["caret^unknown^xquote\""]

  test "reports empty, malformed and unterminated documents":
    check not isValid("")
    check not isValid("BEGIN:VCARD\r\nBROKEN\r\n")
    check detectKind("FN:Ada") == dkUnknown
    check detectKind("BEGIN:OTHER\r\nEND:OTHER\r\n") == dkUnknown
    check validationJson("").contains("empty document")
    check not isValid("FN:Ada\r\n")
    check not isValid("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\n")
    check not isValid("BEGIN:OTHER\r\nEND:OTHER\r\n")
    expect ComponentParseError: discard parseComponents("END:VCARD\r\n")

  test "preserves unknown properties, order and nested components":
    let source = "BEGIN:VCALENDAR\r\nPRODID:-//Concordia//EN\r\nVERSION:2.0\r\nX-WR-CALNAME:Équipe\r\nBEGIN:VEVENT\r\nUID:event-1\r\nDTSTAMP:20260801T120000Z\r\nX-CUSTOM;X-PARAM=one:opaque\\,value\r\nBEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT5M\r\nEND:VALARM\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
    let parsed = parseComponents(source)
    check parsed.len == 1
    check parsed[0].properties("X-WR-CALNAME")[0].value == "Équipe"
    check parsed[0].children("VEVENT")[0].children("VALARM").len == 1
    let normalized = serializeComponents(parsed)
    check normalizeDocument(normalized) == normalized
    check normalized.contains("X-CUSTOM;X-PARAM=one:opaque\\,value")

  test "enforces vCard 4 and iCalendar required properties":
    check not isValid("BEGIN:VCARD\r\nFN:Ada\r\nVERSION:4.0\r\nEND:VCARD\r\n")
    check not isValid("BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Ada\r\nEND:VCARD\r\n")
    check not isValid("BEGIN:VCARD\r\nVERSION:4.0\r\nEND:VCARD\r\n")
    check not isValid("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:1\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n")
    check not isValid("BEGIN:VCALENDAR\r\nPRODID:x\r\nVERSION:1.0\r\nEND:VCALENDAR\r\n")
    check not isValid("BEGIN:VCARD\r\nVERSION:4.0\r\nVERSION:4.0\r\nFN:Ada\r\nEND:VCARD\r\n")
    check not isValid("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:a\r\nPRODID:b\r\nBEGIN:VEVENT\r\nUID:1\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n")
    check isValid("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:\r\nEND:VCARD\r\n")
    check not isValid("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nKIND:unknown\r\nEND:VCARD\r\n")
    check not isValid("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nREV:20260801T120000\r\nEND:VCARD\r\n")
    check not isValid("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nUID:one\r\nUID:two\r\nEND:VCARD\r\n")
    check not isValid("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nUID:\r\nEND:VCARD\r\n")
    check not isValid("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nUID:relative-id\r\nEND:VCARD\r\n")
    check not isValid("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nGENDER:X\r\nEND:VCARD\r\n")
    check isValid("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nGENDER:F;woman\r\nEND:VCARD\r\n")
    check isValid("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nBDAY:--0412T0945\r\nEND:VCARD\r\n")
    check isValid("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nBDAY:---12\r\nEND:VCARD\r\n")
    check isValid("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nBDAY:1985-04\r\nEND:VCARD\r\n")
    check isValid("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nBDAY:--04\r\nEND:VCARD\r\n")
    check isValid("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nBDAY:T0945Z\r\nEND:VCARD\r\n")
    check isValid("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nBDAY:T-45\r\nEND:VCARD\r\n")
    check isValid("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nBDAY:T--30Z\r\nEND:VCARD\r\n")
    check isValid("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nBDAY:19850412T09+01\r\nEND:VCARD\r\n")
    check not isValid("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nBDAY:1985-04T09\r\nEND:VCARD\r\n")
    check not isValid("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nBDAY:--0230\r\nEND:VCARD\r\n")
    check not isValid("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nBDAY:1985-13\r\nEND:VCARD\r\n")
    check not isValid("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nBDAY:--0412T2460\r\nEND:VCARD\r\n")

  test "validates bounded RFC 6350 vCard values and parameters":
    let valid = "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:urn:uuid:ada\r\n" &
      "FN:Ada\r\nBDAY:19850412\r\nANNIVERSARY:---15T094500+0100\r\n" &
      "GEO:geo:51.5,-0.1\r\nEMAIL;PREF=100;PID=1.2:ada@example.test\r\n" &
      "END:VCARD\r\n"
    check isValid(valid)
    check isValid(valid.replace("END:VCARD", "N:Lovelace;Ada;;;\r\nEND:VCARD"))
    check isValid(valid.replace("END:VCARD",
      "ADR:;;123 Main St;London;;SW1A;UK\r\nEND:VCARD"))
    check isValid(valid.replace("END:VCARD",
      "CLIENTPIDMAP:1;https://example.test/card\r\nEND:VCARD"))
    check isValid(valid.replace("END:VCARD", "KIND:x-example\r\nEND:VCARD"))
    for invalid in [
        valid.replace("BDAY:19850412", "BDAY:19850230"),
        valid.replace("EMAIL;PREF=100", "EMAIL;PREF=0"),
        valid.replace("EMAIL;PREF=100", "EMAIL;PREF=101"),
        valid.replace("EMAIL;PREF=100", "EMAIL;PREF=1;PREF=2"),
        valid.replace("EMAIL;PREF=100", "EMAIL;TYPE=home;TYPE=work;PREF=100"),
        valid.replace("PID=1.2", "PID=1."),
        valid.replace("GEO:geo:51.5,-0.1", "GEO:geo:51.5, -0.1"),
        valid.replace("GEO:geo:51.5,-0.1", "GEO:51.5,-0.1"),
        valid.replace("UID:urn:uuid:ada", "UID:urn uuid:ada"),
        valid.replace("END:VCARD", "URL:relative/profile\r\nEND:VCARD"),
        valid.replace("END:VCARD", "RELATED:relative/contact\r\nEND:VCARD"),
        valid.replace("END:VCARD",
          "CLIENTPIDMAP:1;relative/card\r\nEND:VCARD"),
        valid.replace("END:VCARD", "N:Lovelace;Ada\r\nEND:VCARD"),
        valid.replace("END:VCARD", "ADR:;;123 Main St\r\nEND:VCARD"),
        valid.replace("END:VCARD", "CLIENTPIDMAP:0;https://example.test/card\r\nEND:VCARD"),
        valid.replace("END:VCARD", "CLIENTPIDMAP:1;not a uri\r\nEND:VCARD")]:
      check not isValid(invalid)

  test "validates RFC 5545 component value constraints without dropping extensions":
    let valid = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\n" &
      "METHOD:REQUEST\r\nBEGIN:VEVENT\r\nUID:event\r\nDTSTAMP:20260801T120000Z\r\nDTSTART:20260801T120000Z\r\nSTATUS:CONFIRMED\r\n" &
      "CLASS:PRIVATE\r\nTRANSP:OPAQUE\r\nPRIORITY:5\r\nSEQUENCE:2\r\n" &
      "BEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT5M\r\nDESCRIPTION:Reminder\r\nREPEAT:1\r\nDURATION:PT5M\r\n" &
      "X-VENDOR:kept\r\nEND:VALARM\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
    check isValid(valid)
    check isValid(valid.replace("METHOD:REQUEST", "METHOD:X-CUSTOM"))
    check isValid(valid.replace("METHOD:REQUEST", "METHOD:VENDOR-42"))
    check isValid(valid.replace("CLASS:PRIVATE", "CLASS:X-CONFIDENTIAL"))
    check isValid(valid.replace("CLASS:PRIVATE", "CLASS:VENDOR-PRIVATE"))
    check not isValid(valid.replace("CLASS:PRIVATE", "CLASS:VENDOR_PRIVATE"))
    check normalizeDocument(valid).contains("X-VENDOR:kept\r\n")
    check isValid(valid.replace("END:VEVENT",
      "ATTACH:https://example.test/file.bin\r\nEND:VEVENT"))
    check isValid(valid.replace("END:VEVENT",
      "ATTACH;VALUE=BINARY;ENCODING=BASE64;FMTTYPE=application/octet-stream:SGVsbG8=\r\nEND:VEVENT"))
    check not isValid(valid.replace("END:VEVENT",
        "ATTACH:not a URI\r\nEND:VEVENT"))
    check not isValid(valid.replace("END:VEVENT",
      "ATTACH;VALUE=BINARY:SGVsbG8=\r\nEND:VEVENT"))
    check not isValid(valid.replace("END:VEVENT",
      "ATTACH;VALUE=BINARY;ENCODING=BASE64:invalid\r\nEND:VEVENT"))
    for invalid in [
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:x\r\nMETHOD:BAD_METHOD\r\nBEGIN:VEVENT\r\nUID:1\r\nDTSTAMP:20260801T120000Z\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:x\r\nBEGIN:VEVENT\r\nUID:1\r\nDTSTAMP:20260801T120000Z\r\nSTATUS:INVALID\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:x\r\nBEGIN:VTODO\r\nUID:1\r\nDTSTAMP:20260801T120000Z\r\nPERCENT-COMPLETE:101\r\nEND:VTODO\r\nEND:VCALENDAR\r\n",
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:x\r\nBEGIN:VEVENT\r\nUID:1\r\nDTSTAMP:20260801T120000Z\r\nDTEND:20260801T110000Z\r\nDURATION:PT1H\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:x\r\nBEGIN:VEVENT\r\nUID:1\r\nDTSTAMP:20260801T120000Z\r\nBEGIN:VALARM\r\nACTION:DISPLAY\r\nEND:VALARM\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"]:
      check not isValid(invalid)

  test "enforces required RFC 5545 component properties":
    let freeBusy = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\n" &
      "BEGIN:VFREEBUSY\r\nUID:busy\r\nDTSTAMP:20260801T120000Z\r\n" &
      "DTSTART:20260801T000000Z\r\nDTEND:20260802T000000Z\r\n" &
      "FREEBUSY;FBTYPE=BUSY:20260801T100000Z/20260801T110000Z\r\n" &
      "END:VFREEBUSY\r\nEND:VCALENDAR\r\n"
    check isValid(freeBusy)
    check isValid(freeBusy.replace("FBTYPE=BUSY", "FBTYPE=X-COMPANY-BUSY"))
    check isValid(freeBusy.replace("FBTYPE=BUSY", "FBTYPE=VENDOR-BUSY"))
    check not isValid(freeBusy.replace("FREEBUSY;FBTYPE=BUSY:",
      "FREEBUSY;TZID=Europe/Paris;FBTYPE=BUSY:"))
    check isValid(freeBusy.replace("END:VFREEBUSY",
        "FREEBUSY:20260801T120000Z/PT1H\r\nEND:VFREEBUSY"))
    check isValid(freeBusy.replace("END:VFREEBUSY",
        "FREEBUSY;FBTYPE=UNKNOWN:20260801T100000Z/20260801T110000Z\r\nEND:VFREEBUSY"))
    check not isValid(freeBusy.replace("END:VFREEBUSY",
        "FREEBUSY;FBTYPE=UNKNOWN VALUE:20260801T100000Z/20260801T110000Z\r\nEND:VFREEBUSY"))
    check not isValid(freeBusy.replace("END:VFREEBUSY",
        "FREEBUSY:20260801T100000/20260801T110000Z\r\nEND:VFREEBUSY"))
    check not isValid(freeBusy.replace("END:VFREEBUSY",
        "FREEBUSY:20260801T110000Z/20260801T100000Z\r\nEND:VFREEBUSY"))
    check not isValid(freeBusy.replace("END:VFREEBUSY",
        "FREEBUSY:20260801T100000Z/PT0S\r\nEND:VFREEBUSY"))
    check not isValid(freeBusy.replace("DTSTART:20260801T000000Z",
      "DTSTART:20260801T000000"))
    check not isValid(freeBusy.replace("DTSTAMP:20260801T120000Z\r\n", ""))
    let freeBusyReply = freeBusy.replace(
      "DTSTART:20260801T000000Z\r\nDTEND:20260802T000000Z\r\n", "")
    check isValid(freeBusyReply)
    check isValid(freeBusy.replace("END:VFREEBUSY\r\n",
      "ATTENDEE:mailto:attendee@example.test\r\nEND:VFREEBUSY\r\n"))
    for singleton in [
        "CONTACT:mailto:contact@example.test\r\n",
        "ORGANIZER:mailto:organizer@example.test\r\n",
        "URL:https://example.test/freebusy\r\n"]:
      let duplicated = freeBusy.replace("END:VFREEBUSY\r\n",
        singleton & singleton & "END:VFREEBUSY\r\n")
      check not isValid(duplicated)
    let emailAlarm = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\n" &
      "BEGIN:VEVENT\r\nUID:email-alarm\r\nDTSTAMP:20260801T120000Z\r\n" &
      "DTSTART:20260801T120000Z\r\nBEGIN:VALARM\r\nACTION:EMAIL\r\n" &
      "TRIGGER:-PT5M\r\nDESCRIPTION:Reminder\r\nSUMMARY:Reminder\r\n" &
      "ATTENDEE:mailto:attendee@example.test\r\nEND:VALARM\r\n" &
      "END:VEVENT\r\nEND:VCALENDAR\r\n"
    check isValid(emailAlarm)
    for recurrence in ["RRULE:FREQ=DAILY\r\n", "RDATE:20260801T120000Z\r\n",
        "EXDATE:20260801T120000Z\r\n"]:
      check not isValid(freeBusy.replace("END:VFREEBUSY\r\n",
        recurrence & "END:VFREEBUSY\r\n"))
    let timezone = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\n" &
      "BEGIN:VTIMEZONE\r\nTZID:Test/Zone\r\nBEGIN:STANDARD\r\n" &
      "DTSTART:20260101T000000\r\nTZOFFSETFROM:+0100\r\nTZOFFSETTO:+0100\r\n" &
      "END:STANDARD\r\nEND:VTIMEZONE\r\nEND:VCALENDAR\r\n"
    check isValid(timezone)
    check not isValid(timezone.replace("DTSTART:20260101T000000",
      "DTSTART:20260101T000000Z"))
    check not isValid(timezone.replace("DTSTART:20260101T000000",
      "DTSTART;TZID=Europe/Paris:20260101T000000"))
    check isValid(timezone.replace("TZID:Test/Zone\r\n",
      "TZID:Test/Zone\r\nLAST-MODIFIED:20251201T120000Z\r\nTZURL:https://example.test/zone.ics\r\n"))
    check not isValid(timezone.replace("TZID:Test/Zone\r\n",
      "TZID:Test/Zone\r\nLAST-MODIFIED:20251201T120000\r\n"))
    check not isValid(timezone.replace("TZID:Test/Zone\r\n",
      "TZID:Test/Zone\r\nLAST-MODIFIED:20251201T120000Z\r\n" &
      "LAST-MODIFIED:20251202T120000Z\r\n"))
    let secondTimezone = timezone.replace(
      "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\n", "").replace(
        "END:VCALENDAR\r\n", "")
    check not isValid(timezone.replace("END:VCALENDAR\r\n",
      secondTimezone & "END:VCALENDAR\r\n"))
    check not isValid(timezone.replace("TZOFFSETTO:+0100\r\n", ""))
    let recurringTimezone = timezone.replace("END:STANDARD", "" &
      "RRULE:FREQ=YEARLY;BYMONTH=10;BYMONTHDAY=25\r\n" &
      "RDATE:20271025T030000\r\nEND:STANDARD")
    check isValid(recurringTimezone)
    check not isValid(recurringTimezone.replace("FREQ=YEARLY", "FREQ=MONTHLY"))
    check not isValid(recurringTimezone.replace("FREQ=YEARLY;BYMONTH=10;BYMONTHDAY=25",
      "FREQ=YEARLY;BYMONTH=10;BYMONTHDAY=25;UNTIL=20271025T030000"))
    check not isValid(recurringTimezone.replace("RDATE:20271025T030000",
      "RDATE:20271025T030000Z"))
    let availability = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:x\r\n" &
      "BEGIN:VAVAILABILITY\r\nUID:availability\r\nDTSTAMP:20260801T120000Z\r\n" &
      "BUSYTYPE:BUSY\r\nPRIORITY:5\r\n" &
      "BEGIN:AVAILABLE\r\nUID:available\r\nDTSTAMP:20260801T120000Z\r\n" &
      "DTSTART:20260801T090000Z\r\n" &
      "DTEND:20260801T170000Z\r\nEND:AVAILABLE\r\n" &
      "END:VAVAILABILITY\r\nEND:VCALENDAR\r\n"
    check isValid(availability)
    let richAvailability = availability.replace(
      "BUSYTYPE:BUSY\r\nPRIORITY:5\r\n",
      "BUSYTYPE:BUSY\r\nCLASS:PUBLIC\r\nCREATED:20260701T120000Z\r\n" &
      "DESCRIPTION:Working hours\r\nLAST-MODIFIED:20260702T120000Z\r\n" &
      "LOCATION:Office\r\nORGANIZER:mailto:organizer@example.test\r\n" &
      "PRIORITY:5\r\nSEQUENCE:1\r\nSUMMARY:Availability\r\n" &
      "URL:https://example.test/availability\r\n")
      .replace("DTSTART:20260801T090000Z\r\n",
      "CREATED:20260701T120000Z\r\nDESCRIPTION:Morning\r\n" &
      "LAST-MODIFIED:20260702T120000Z\r\nLOCATION:Office\r\n" &
      "SUMMARY:Morning availability\r\nCATEGORIES:WORK\r\nCOMMENT:Open\r\n" &
      "CONTACT:mailto:contact@example.test\r\nDTSTART:20260801T090000Z\r\n")
    check isValid(richAvailability)
    for singleton in ["DESCRIPTION:Duplicate\r\n", "LOCATION:Duplicate\r\n",
        "SUMMARY:Duplicate\r\n", "URL:https://example.test/duplicate\r\n"]:
      check not isValid(availability.replace("BUSYTYPE:BUSY\r\n",
        "BUSYTYPE:BUSY\r\n" & singleton & singleton))
    check isValid(availability.replace("BUSYTYPE:BUSY", "BUSYTYPE:UNKNOWN"))
    check not isValid(availability.replace("BUSYTYPE:BUSY",
        "BUSYTYPE:UNKNOWN VALUE"))
    check isValid(availability.replace("BUSYTYPE:BUSY",
        "BUSYTYPE:X-COMPANY-BUSY"))
    check isValid(availability.replace("BUSYTYPE:BUSY",
        "BUSYTYPE:VENDOR-BUSY"))
    check not isValid(availability.replace("BUSYTYPE:BUSY", "BUSYTYPE:FREE"))
    check not isValid(availability.replace("UID:available\r\n", ""))
    check not isValid(availability.replace("DTSTART:20260801T090000Z",
      "DTSTART;VALUE=DATE:20260801"))
    check not isValid(availability.replace("DTSTART:20260801T090000Z",
      "DTSTART:20260801T090000"))
    check isValid(availability.replace("DTEND:20260801T170000Z",
      "DTEND:20260801T170000Z\r\nRRULE:FREQ=WEEKLY;BYDAY=MO,WE"))
    check isValid(availability.replace("DTEND:20260801T170000Z",
      "DTEND:20260801T170000Z\r\nRDATE:20260802T090000Z\r\n" &
      "EXDATE:20260803T090000Z"))
    check not isValid(availability.replace("END:VAVAILABILITY",
      "RRULE:FREQ=WEEKLY\r\nEND:VAVAILABILITY"))
    check not isValid(availability.replace("DTEND:20260801T170000Z",
      "DTEND:20260801T170000Z\r\nRRULE:FREQ=INVALID"))
    check not isValid(availability.replace("DTEND:20260801T170000Z\r\nEND:AVAILABLE",
      "DTEND:20260801T170000Z\r\nDURATION:PT1H\r\nEND:AVAILABLE"))
    check not isValid(availability.replace("DTEND:20260801T170000Z",
      "DTEND:20260801T170000Z\r\nDURATION:PT1H"))
    let availabilityZone = "BEGIN:VTIMEZONE\r\nTZID:Test/Zone\r\n" &
      "BEGIN:STANDARD\r\nDTSTART:20260101T000000\r\n" &
      "TZOFFSETFROM:+0100\r\nTZOFFSETTO:+0100\r\nEND:STANDARD\r\n" &
      "END:VTIMEZONE\r\n"
    let zonedAvailability = availability
      .replace("DTSTART:20260801T090000Z", "DTSTART;TZID=Test/Zone:20260801T090000")
      .replace("DTEND:20260801T170000Z", "DTEND;TZID=Test/Zone:20260801T170000")
      .replace("END:VCALENDAR\r\n", availabilityZone & "END:VCALENDAR\r\n")
    check isValid(zonedAvailability)
    check not isValid(zonedAvailability.replace("TZID=Test/Zone",
        "TZID=Missing/Zone"))
    check not isValid(availability
      .replace("DTSTART:20260801T090000Z",
          "DTSTART;TZID=Missing/Zone:20260801T090000"))
    let journal = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:x\r\n" &
      "BEGIN:VJOURNAL\r\nUID:journal\r\nDTSTAMP:20260801T120000Z\r\n" &
      "DESCRIPTION:First entry\r\nDESCRIPTION:Second entry\r\n" &
      "END:VJOURNAL\r\nEND:VCALENDAR\r\n"
    check isValid(journal)
    check not isValid(journal.replace("VJOURNAL", "VEVENT"))
    let completedTodo = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:x\r\n" &
      "BEGIN:VTODO\r\nUID:todo\r\nDTSTAMP:20260801T120000Z\r\n" &
      "STATUS:COMPLETED\r\nCOMPLETED:20260801T130000Z\r\n" &
      "END:VTODO\r\nEND:VCALENDAR\r\n"
    check isValid(completedTodo)
    check not isValid(completedTodo.replace(
      "COMPLETED:20260801T130000Z\r\n", ""))
    let durationTodo = completedTodo.replace(
      "STATUS:COMPLETED\r\nCOMPLETED:20260801T130000Z\r\n",
      "DURATION:PT1H\r\n")
    check not isValid(durationTodo)
    check isValid(durationTodo.replace("DTSTAMP:20260801T120000Z\r\n",
      "DTSTAMP:20260801T120000Z\r\nDTSTART:20260801T110000Z\r\n"))

  test "rejects malformed RFC 5545 temporal values":
    let base = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\n" &
      "BEGIN:VEVENT\r\nUID:event\r\nDTSTAMP:20260801T120000Z\r\n" &
      "DTSTART:20260802T120000Z\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
    check isValid(base)
    check isValid(base.replace("DTSTART:20260802T120000Z",
      "DTSTART:20260802T115960Z"))
    check not isValid(base.replace("DTSTART:20260802T120000Z",
      "DTSTART:20260802T116100Z"))
    check not isValid(base.replace("DTSTAMP:20260801T120000Z",
      "DTSTAMP:20260801T120000"))
    check not isValid(base.replace("DTSTART:20260802T120000Z",
      "DTSTART:20260230T120000Z"))
    check isValid(base.replace("END:VEVENT",
      "RRULE:FREQ=DAILY;INTERVAL=2;COUNT=3\r\nEND:VEVENT"))
    check isValid(base.replace("END:VEVENT",
      "RDATE:20260803T120000Z\r\nEXDATE:20260804T120000Z\r\n" &
      "RDATE;VALUE=PERIOD:20260805T120000Z/PT1H\r\nEND:VEVENT"))
    check isValid(base.replace("END:VEVENT",
      "DTEND:20260803T120000Z\r\nEND:VEVENT"))
    check isValid(base.replace("END:VEVENT",
      "ORGANIZER:mailto:organizer@example.test\r\n" &
      "ATTENDEE:mailto:attendee@example.test\r\nEND:VEVENT"))
    check isValid(base.replace("END:VEVENT",
      "URL:https://example.test/events/event.ics\r\nEND:VEVENT"))
    check not isValid(base.replace("END:VEVENT",
      "URL:event path\r\nEND:VEVENT"))
    check isValid(base.replace("END:VEVENT",
      "RELATED-TO:https://example.test/events/parent.ics\r\nEND:VEVENT"))
    check not isValid(base.replace("END:VEVENT",
      "RELATED-TO:parent event\r\nEND:VEVENT"))
    check isValid(base.replace("END:VEVENT",
      "REQUEST-STATUS:2.0;Success\r\nEND:VEVENT"))
    check isValid(base.replace("END:VEVENT",
      "REQUEST-STATUS:2.8;Success\\;repeating;RRULE:FREQ=WEEKLY\r\nEND:VEVENT"))
    for badStatus in ["REQUEST-STATUS:2;Success\r\n",
        "REQUEST-STATUS:2.0.1.2;Too granular\r\n",
        "REQUEST-STATUS:2.a;Invalid\r\n",
        "REQUEST-STATUS:2.0\r\n"]:
      check not isValid(base.replace("END:VEVENT", badStatus & "END:VEVENT"))
    check isValid(base.replace("END:VEVENT",
        "GEO:48.8566;2.3522\r\nEND:VEVENT"))
    check not isValid(base.replace("END:VEVENT", "GEO:91;2\r\nEND:VEVENT"))
    check not isValid(base.replace("END:VEVENT", "GEO:48;181\r\nEND:VEVENT"))
    check not isValid(base.replace("END:VEVENT", "GEO:48\r\nEND:VEVENT"))
    check not isValid(base.replace("END:VEVENT", "GEO:4.8e1;2\r\nEND:VEVENT"))
    check not isValid(base.replace("END:VEVENT", "GEO:.5;2\r\nEND:VEVENT"))
    check not isValid(base.replace("END:VEVENT", "GEO:48.;2\r\nEND:VEVENT"))
    check not isValid(base.replace("END:VEVENT",
      "ATTENDEE:not-an-address\r\nEND:VEVENT"))
    check not isValid(base.replace("END:VEVENT",
      "DTEND:20260801T120000Z\r\nEND:VEVENT"))
    check not isValid(base.replace("END:VEVENT",
      "DTEND;VALUE=DATE:20260803\r\nEND:VEVENT"))
    for badRule in ["RRULE:INTERVAL=0\r\n", "RRULE:FREQ=DAILY;COUNT=0\r\n",
        "RRULE:FREQ=DAILY;COUNT=2;UNTIL=20260804T120000Z\r\n",
        "RRULE:FREQ=MONTHLY;BYDAY=0MO\r\n",
        "RRULE:FREQ=MONTHLY;BYDAY=001MO\r\n",
        "RRULE:FREQ=MONTHLY;BYDAY=+001MO\r\n",
        "RRULE:FREQ=MONTHLY;BYDAY=+MO\r\n",
        "RRULE:FREQ=MONTHLY;BYSETPOS=-1\r\n",
        "RRULE:FREQ=YEARLY;BYWEEKNO=1;BYDAY=1MO\r\n",
        "RRULE:FREQ=YEARLY;BYMONTH=13\r\n",
        "RRULE:FREQ=DAILY;UNTIL=20260804T120000\r\n",
        "RRULE:FREQ=DAILY;UNTIL=20260801T120000Z\r\n"]:
      check not isValid(base.replace("END:VEVENT", badRule & "END:VEVENT"))
    for badDate in ["RDATE:20260230T120000Z\r\n",
        "EXDATE;VALUE=PERIOD:20260803T120000Z/PT1H\r\n",
        "RDATE;VALUE=TEXT:20260803T120000Z\r\n",
        "EXDATE;VALUE=TEXT:20260803T120000Z\r\n",
        "RDATE;VALUE=DATE;TZID=Europe/Paris:20260803\r\n",
        "EXDATE;TZID=Europe/Paris:20260803T120000Z\r\n",
        "RDATE;VALUE=PERIOD;TZID=Europe/Paris:20260803T120000Z/PT1H\r\n",
        "RECURRENCE-ID;VALUE=TEXT:20260803T120000Z\r\n",
        "RECURRENCE-ID;VALUE=DATE;RANGE=THISANDFUTURE:20260803\r\n",
        "RDATE;VALUE=PERIOD:20260803T120000Z/not-a-duration\r\n",
        "RDATE;VALUE=PERIOD:20260803T120000Z/20260803T110000Z\r\n",
        "RDATE;VALUE=PERIOD:20260803T120000Z/PT0S\r\n",
        "RECURRENCE-ID:20260803\r\n"]:
      check not isValid(base.replace("END:VEVENT", badDate & "END:VEVENT"))
    let badDuration = base.replace("END:VEVENT", "DURATION:PXT\r\nEND:VEVENT")
    check not isValid(badDuration)
    check isValid(base.replace("END:VEVENT", "DURATION:P1W\r\nEND:VEVENT"))
    check isValid(base.replace("END:VEVENT", "DURATION:P1DT1H\r\nEND:VEVENT"))
    check not isValid(base.replace("END:VEVENT",
        "DURATION:P1W2D\r\nEND:VEVENT"))
    check not isValid(base.replace("END:VEVENT",
      "DURATION:PT1H1H\r\nEND:VEVENT"))
    let freeBusy = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:x\r\n" &
      "BEGIN:VFREEBUSY\r\nUID:busy\r\nDTSTAMP:20260801T120000Z\r\n" &
      "FREEBUSY:20260802T100000Z/PT1H\r\nEND:VFREEBUSY\r\n" &
      "END:VCALENDAR\r\n"
    check isValid(freeBusy)
    check not isValid(freeBusy.replace("FREEBUSY:", "FREEBUSY;VALUE=TEXT:"))
    check not isValid(freeBusy.replace("FREEBUSY:",
      "FREEBUSY;FBTYPE=BUSY,FREE:"))
    let badTimezone = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:x\r\n" &
      "BEGIN:VTIMEZONE\r\nTZID:Test/Zone\r\nBEGIN:STANDARD\r\n" &
      "DTSTART:20260101T000000\r\nTZOFFSETFROM:+2500\r\n" &
      "TZOFFSETTO:+0100\r\nEND:STANDARD\r\nEND:VTIMEZONE\r\n" &
      "END:VCALENDAR\r\n"
    check not isValid(badTimezone)

  test "enforces RFC 5545 component cardinality and placement":
    let base = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:x\r\n" &
      "BEGIN:VEVENT\r\nUID:event\r\nDTSTAMP:20260801T120000Z\r\nDTSTART:20260801T120000Z\r\n" &
      "BEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT5M\r\n" &
      "DESCRIPTION:Reminder\r\nEND:VALARM\r\nEND:VEVENT\r\n" &
      "END:VCALENDAR\r\n"
    check isValid(base)
    check not isValid(base.replace("DTSTART:20260801T120000Z\r\n", ""))
    check not isValid(base.replace("TRIGGER:-PT5M",
      "TRIGGER;RELATED=END:-PT5M"))
    check isValid(base.replace("TRIGGER:-PT5M",
      "TRIGGER;RELATED=END:-PT5M").replace(
        "DTSTART:20260801T120000Z", "DTSTART:20260801T120000Z\r\nDTEND:20260801T130000Z"))
    check not isValid(base.replace("DESCRIPTION:Reminder\r\n", ""))
    check not isValid(base.replace("ACTION:DISPLAY", "ACTION:INVALID"))
    check not isValid(base.replace("END:VEVENT",
      "PERCENT-COMPLETE:10\r\nEND:VEVENT"))
    check not isValid(base.replace("END:VEVENT",
      "DUE:20260801T130000Z\r\nEND:VEVENT"))
    check not isValid(base.replace("END:VEVENT",
      "LOCATION:Room\r\nEND:VEVENT").replace("BEGIN:VEVENT", "BEGIN:VJOURNAL")
      .replace("END:VEVENT", "END:VJOURNAL"))
    let todoPlacement = base.replace("BEGIN:VEVENT", "BEGIN:VTODO")
      .replace("END:VEVENT", "END:VTODO")
    check not isValid(todoPlacement.replace("END:VTODO",
      "TRANSP:OPAQUE\r\nEND:VTODO"))
    let misplaced = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:x\r\n" &
      "BEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT5M\r\n" &
      "DESCRIPTION:Misplaced\r\nEND:VALARM\r\nEND:VCALENDAR\r\n"
    check not isValid(misplaced)
    check not isValid(base.replace("DTSTAMP:20260801T120000Z\r\n",
      "DTSTAMP:20260801T120000Z\r\nDTSTAMP:20260801T120001Z\r\n"))
    let twoCalendars = base & base
    check not isValid(twoCalendars)
    check not isValid(base.replace("END:VEVENT\r\nEND:VCALENDAR",
      "END:VEVENT\r\nBEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT5M\r\n" &
      "DESCRIPTION:Misplaced\r\nEND:VALARM\r\nEND:VCALENDAR"))
    check not isValid(base.replace("ACTION:DISPLAY", "ACTION:AUDIO").replace(
      "DESCRIPTION:Reminder", "SUMMARY:Not allowed"))
    check not isValid(base.replace("TRIGGER:-PT5M",
      "TRIGGER;VALUE=DATE-TIME;RELATED=START:20260801T120000Z"))
    check isValid(base.replace("ACTION:DISPLAY", "ACTION:AUDIO").replace(
      "DESCRIPTION:Reminder", "ATTACH;FMTTYPE=audio/basic:http://example.test/beep"))
    check not isValid(base.replace("PRODID:x", "PRODID:"))
    check not isValid(base.replace("END:VCALENDAR",
        "CALSCALE:ISLAMIC\r\nEND:VCALENDAR"))
    check not isValid(base.replace("END:VCALENDAR",
        "CALSCALE:GREGORIAN\r\nCALSCALE:GREGORIAN\r\nEND:VCALENDAR"))
    let recurrenceId = base.replace("END:VEVENT", "RECURRENCE-ID;RANGE=INVALID:20260802T120000Z\r\nEND:VEVENT")
    check not isValid(recurrenceId)
    let temporalBase = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:x\r\n" &
      "BEGIN:VEVENT\r\nUID:temporal\r\nDTSTAMP:20260801T120000Z\r\n" &
      "DTSTART:20260802T120000Z\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
    check not isValid(temporalBase.replace("DTSTART:20260802T120000Z",
      "DTSTART;TZID=Europe/Paris:20260802T120000Z"))
    check not isValid(temporalBase.replace("DTSTART:20260802T120000Z",
      "DTSTART;TZID=Europe/Paris;VALUE=DATE:20260802"))
    check not isValid(temporalBase.replace("END:VEVENT",
        "DURATION:-PT1H\r\nEND:VEVENT"))
    check not isValid(temporalBase.replace("END:VEVENT",
        "DURATION:PT0S\r\nEND:VEVENT"))
    check not isValid(temporalBase.replace("END:VEVENT",
        "DTSTART;VALUE=PERIOD:20260802T120000Z/PT1H\r\nEND:VEVENT"))
    let twoCards = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:One\r\nEND:VCARD\r\n" &
      "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Two\r\nEND:VCARD\r\n"
    check not isValid(twoCards)
    check isValid("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:One\r\nFN:Two\r\nEND:VCARD\r\n")

  test "rejects component depth overflow and nil serialization":
    let nested = "BEGIN:A\r\nBEGIN:B\r\nBEGIN:C\r\nEND:C\r\nEND:B\r\nEND:A\r\n"
    expect ComponentParseError: discard parseComponents(nested, maxDepth = 2)
    expect ComponentParseError: discard serializeComponent(nil)

  test "edits scalar fields without losing unknown properties or parameters":
    let parsed = parseComponents("BEGIN:VCARD\r\nVERSION:4.0\r\nFN;LANGUAGE=fr:Ancien\r\nFN:duplicate\r\nX-CUSTOM;X-P=1:opaque\r\nEND:VCARD\r\n")
    parsed[0].setTextProperty("FN", "Élodie, Martin", required = true)
    let serialized = serializeComponents(parsed)
    check serialized.contains("FN;LANGUAGE=fr:Élodie\\, Martin\r\n")
    check serialized.count("FN") == 1
    check serialized.contains("X-CUSTOM;X-P=1:opaque\r\n")
    check parsed[0].propertyValue("FN") == "Élodie, Martin"

  test "removes optional fields and rejects unsafe or empty required edits":
    let parsed = parseComponents("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nNOTE:keep\\nthis\r\nEND:VCARD\r\n")
    check parsed[0].propertyValue("NOTE") == "keep\nthis"
    parsed[0].setTextProperty("NOTE", "")
    check parsed[0].properties("NOTE").len == 0
    expect DocumentEditError: parsed[0].setTextProperty("FN", "",
        required = true)
    expect DocumentEditError: parsed[0].setTextProperty("BAD\nNAME", "x")

  test "merges modeled properties while retaining extensions and child order":
    let target = parseComponents("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Old\r\nEMAIL:a@example.test\r\nX-KEEP:opaque\r\nEND:VCARD\r\n")[0]
    let source = parseComponents("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:New\r\nEMAIL;TYPE=work:b@example.test\r\nEMAIL:c@example.test\r\nEND:VCARD\r\n")[0]
    target.replaceProperties(source, ["FN", "EMAIL"])
    let serialized = serializeComponent(target)
    check serialized.contains("FN:New\r\n")
    check serialized.contains("EMAIL;TYPE=work:b@example.test\r\nEMAIL:c@example.test\r\n")
    check not serialized.contains("FN:Old")
    check serialized.contains("X-KEEP:opaque")

  test "projects contacts, events and tasks for thin hosts":
    let card = parseJson(projectionJson("BEGIN:VCARD\r\nVERSION:4.0\r\nUID:urn:uuid:ada\r\nFN:Ada\\, Lovelace\r\nEMAIL:ada@example.test\r\nX-KEEP:opaque\r\nEND:VCARD\r\n"))
    check card["kind"].getStr == "contact"
    check card["@type"].getStr == "Card"
    check card["version"].getStr == "1.0"
    check card["name"]["full"].getStr == "Ada, Lovelace"
    check card["name"]["fullName"].getStr == "Ada, Lovelace"
    check card["emails"]["email0"]["address"].getStr == "ada@example.test"
    let event = parseJson(projectionJson("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\nBEGIN:VEVENT\r\nUID:event\r\nDTSTAMP:20260801T120000Z\r\nSUMMARY:Review\r\nDTSTART:20260802T120000Z\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"))
    check event["kind"].getStr == "event"
    check event["@type"].getStr == "Event"
    check event["title"].getStr == "Review"
    check event["start"].getStr == "2026-08-02T12:00:00Z"
    let zoned = parseJson(projectionJson("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\nBEGIN:VEVENT\r\nUID:zoned\r\nDTSTAMP:20260801T120000Z\r\nSUMMARY:Review\r\nDTSTART:20260802T120000Z\r\nX-CONCORDIA-TIMEZONE:Europe/Paris\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"))
    check zoned["timeZone"].getStr == "Europe/Paris"
    let taskSource = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\nBEGIN:VTODO\r\nUID:task\r\nDTSTAMP:20260801T120000Z\r\nSUMMARY:Ship\r\nDUE:20260803T120000Z\r\nPERCENT-COMPLETE:25\r\nRRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE\r\nEND:VTODO\r\nEND:VCALENDAR\r\n"
    let task = parseJson(projectionJson(taskSource))
    check task["kind"].getStr == "task"
    check task["due"].getStr == "2026-08-03T12:00:00Z"
    check task["percentComplete"].getStr == "25"
    check task["recurrenceRules"][0]["interval"].getInt == 2
    check task["recurrenceRules"][0]["byDay"].len == 2
    let jsContactExtensions = parseJson(projectionJson(
      "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:urn:uuid:js\r\nFN:Ada Lovelace\r\n" &
      "CREATED:20260801T120000Z\r\nLANGUAGE:en-GB\r\nLANG;TYPE=work;PREF=1:fr\r\n" &
      "PRONOUNS;TYPE=work:they/them\r\n" &
      "EMAIL;TYPE=work;PREF=1:ada@example.test\r\n" &
      "TEL;TYPE=cell,voice:+33123456789\r\n" &
      "SOCIALPROFILE;SERVICE-TYPE=Mastodon:https://example.test/@ada\r\n" &
      "END:VCARD\r\n"))
    check jsContactExtensions["created"].getStr == "2026-08-01T12:00:00Z"
    check jsContactExtensions["language"].getStr == "en-GB"
    check jsContactExtensions["preferredLanguages"]["lang0"][
        "language"].getStr == "fr"
    check jsContactExtensions["preferredLanguages"]["lang0"]["pref"].getInt == 1
    check jsContactExtensions["pronouns"]["pronouns0"]["value"].getStr == "they/them"
    check jsContactExtensions["emails"]["email0"]["contexts"]["work"].getBool
    check jsContactExtensions["emails"]["email0"]["pref"].getInt == 1
    check jsContactExtensions["phones"]["phone0"]["features"]["cell"].getBool
    check jsContactExtensions["onlineServices"]["social0"]["service"].getStr == "Mastodon"

    let editedTask = patchedDocument(taskSource, $(%*{"summary": "Shipped",
      "description": "",
      "location": "", "start": "", "due": "2026-08-04T12:00:00Z",
      "completed": "2026-08-01T13:00:00Z", "percentComplete": "100",
      "status": "completed"}))
    check editedTask.contains("SUMMARY:Shipped")
    check editedTask.contains("DUE:20260804T120000Z")
    check editedTask.contains("COMPLETED:20260801T130000Z")
    check editedTask.contains("PERCENT-COMPLETE:100")
    check editedTask.contains("STATUS:COMPLETED")
    let jsContactPatch = patchedDocument(
      "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:urn:uuid:js\r\nFN:Old\r\nEND:VCARD\r\n",
      $(%*{"name": {"full": "New"}, "organizations": {}, "titles": {},
        "emails": {}, "phones": {}, "notes": {}}))
    check jsContactPatch.contains("FN:New")
    let jsCalendarPatch = patchedDocument(
      "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\nBEGIN:VEVENT\r\nUID:js\r\nDTSTAMP:20260801T120000Z\r\nSUMMARY:Old\r\nDTSTART:20260802T120000Z\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
      $(%*{"title": "New", "description": "", "location": "",
        "start": "2026-08-02T12:00:00Z"}))
    check jsCalendarPatch.contains("SUMMARY:New")
    let safeRule = patchedDocument(taskSource, $(%*{"summary": "Ship",
      "description": "",
      "location": "", "start": "", "recurrenceRule":
      "FREQ=MONTHLY;INTERVAL=2;BYDAY=1MO,-1FR;BYMONTH=1,12;BYMONTHDAY=-1;WKST=MO"}))
    check parseComponents(safeRule)[0].children("VTODO")[0].propertyValue(
        "RRULE") ==
      "FREQ=MONTHLY;INTERVAL=2;BYDAY=1MO,-1FR;BYMONTH=1,12;BYMONTHDAY=-1;WKST=MO"
    for unsafeRule in ["FREQ=WEEKLY;INTERVAL=abc", "FREQ=DAILY;FREQ=WEEKLY",
        "FREQ=DAILY;COUNT=2;UNTIL=20260804T120000Z", "FREQ=MONTHLY;BYDAY=0MO",
        "FREQ=YEARLY;BYMONTH=13", "FREQ=DAILY;BYSECOND=60"]:
      expect DocumentEditError:
        discard patchedDocument(taskSource, $(%*{"summary": "Ship",
          "description": "",
          "location": "", "start": "", "recurrenceRule": unsafeRule}))
    let fineRule = patchedDocument(taskSource, $(%*{"summary": "Ship",
      "description": "", "location": "", "start": "",
      "recurrenceRule": "FREQ=HOURLY;BYMINUTE=0,30;COUNT=2"}))
    check parseComponents(fineRule)[0].children("VTODO")[0].propertyValue(
        "RRULE") == "FREQ=HOURLY;BYMINUTE=0,30;COUNT=2"
    let dateStartTask = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\n" &
      "BEGIN:VTODO\r\nUID:date-rule\r\nDTSTAMP:20260801T120000Z\r\nDTSTART;VALUE=DATE:20260803\r\n" &
      "SUMMARY:Date\r\nEND:VTODO\r\nEND:VCALENDAR\r\n"
    let dateRule = patchedDocument(dateStartTask, $(%*{"summary": "Date",
      "description": "", "location": "", "start": "",
      "recurrenceRule": "FREQ=DAILY;UNTIL=20260810"}))
    check parseComponents(dateRule)[0].children("VTODO")[0].propertyValue(
        "RRULE") == "FREQ=DAILY;UNTIL=20260810"
    expect DocumentEditError:
      discard patchedDocument(dateStartTask, $(%*{"summary": "Date",
        "description": "", "location": "", "start": "",
        "recurrenceRule": "FREQ=DAILY;UNTIL=20260810T000000Z"}))

  test "patches projected fields without dropping unknown source data":
    let original = "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:urn:uuid:ada\r\nFN:Ada\r\nEMAIL:old@example.test\r\nEMAIL:secondary@example.test\r\nX-KEEP:opaque\r\nEND:VCARD\r\n"
    let patch = $(%*{"name": {"fullName": "Ada Lovelace"},
      "emails": {"email0": {"address": "new@example.test"}},
      "organizations": {}, "titles": {}, "phones": {}, "notes": {}})
    let updated = patchedDocument(original, patch)
    check updated.contains("FN:Ada Lovelace")
    check updated.contains("EMAIL:new@example.test")
    check updated.contains("EMAIL:secondary@example.test")
    check updated.contains("X-KEEP:opaque")

  test "converts bounded JSContact cards without dropping vCard extensions":
    let source = "BEGIN:VCARD\r\nVERSION:4.0\r\n" &
      "FN:Ada Lovelace\r\nEMAIL;TYPE=work;PREF=1:ada@example.test\r\n" &
      "X-EXAMPLE:kept\r\nEND:VCARD\r\n"
    let js = parseJson(jsContactFromVCard(source))
    check js["@type"].getStr == "Card"
    check js["version"].getStr == "2.0"
    check js["uid"].getStr == ""
    check js["vCardProps"][0][0].getStr == "x-example"
    let restored = vCardFromJsContact($js)
    check restored.contains("FN:Ada Lovelace\r\n")
    check restored.contains("EMAIL;TYPE=work;PREF=1:ada@example.test\r\n")
    check restored.contains("X-EXAMPLE:kept\r\n")
    check validateJsContact($js)
    let emptyCard = vCardFromJsContact("{\"@type\":\"Card\",\"version\":\"2.0\"}")
    check emptyCard.contains("FN:\r\n")
    let withExtension = vCardFromJsContact(
      "{\"@type\":\"Card\",\"version\":\"2.0\",\"example.test:foo\":{\"bar\":true}}")
    check withExtension.contains("JSPROP;JSPTR=\"example.test:foo\":")
    let extensionRoundTrip = parseJson(jsContactFromVCard(withExtension))
    check extensionRoundTrip["example.test:foo"]["bar"].getBool
    let slashExtension = vCardFromJsContact(
      "{\"@type\":\"Card\",\"version\":\"2.0\",\"vendor/foo\":7}")
    check slashExtension.contains("JSPTR=vendor~1foo:7")
    let slashRoundTrip = parseJson(jsContactFromVCard(slashExtension))
    check slashRoundTrip["vendor/foo"].getInt == 7
    let nestedExtension = vCardFromJsContact(
      "{\"@type\":\"Card\",\"version\":\"2.0\",\"phones\":{\"phone0\":{" &
      "\"number\":\"tel:+33123456789\",\"vendor/foo\":\"opaque\"}}}")
    check nestedExtension.contains("JSPTR=phones/phone0/vendor~1foo:")
    let nestedRoundTrip = parseJson(jsContactFromVCard(nestedExtension))
    check nestedRoundTrip["phones"]["phone0"]["vendor/foo"].getStr == "opaque"
    let labeled = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Labeled\r\n" &
      "item1.TEL;TYPE=cell:tel:+33123456789\r\n" &
      "item1.X-ABLabel:Mobile\r\nEND:VCARD\r\n"
    let labeledJs = parseJson(jsContactFromVCard(labeled))
    check labeledJs["phones"]["phone0"]["label"].getStr == "Mobile"
    check vCardFromJsContact($labeledJs).contains("X-ABLABEL:Mobile\r\n")
    let propIdCard = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:IDs\r\n" &
      "TEL;PROP-ID=PHONE-A;TYPE=voice:tel:+33123456789\r\nEND:VCARD\r\n"
    let propIdJs = parseJson(jsContactFromVCard(propIdCard))
    check propIdJs["phones"].hasKey("PHONE-A")
    check vCardFromJsContact($propIdJs).contains("PROP-ID=PHONE-A")
    let linkedOrganization = vCardFromJsContact(
      "{\"@type\":\"Card\",\"version\":\"2.0\",\"organizations\":{" &
      "\"org0\":{\"name\":\"Example Corp\"}},\"titles\":{" &
      "\"title0\":{\"kind\":\"role\",\"name\":\"Lead\"," &
      "\"organizationId\":\"org0\"}}}")
    check linkedOrganization.contains("org0.ORG:Example Corp\r\n")
    check linkedOrganization.contains("org0.ROLE:Lead\r\n")
    let linkedRoundTrip = parseJson(jsContactFromVCard(linkedOrganization))
    check linkedRoundTrip["titles"]["title0"]["organizationId"].getStr == "org0"
    expect JsContactError:
      discard vCardFromJsContact("{\"@type\":\"Card\",\"version\":\"1.0\"}")

    let structured = "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:urn:uuid:structured\r\n" &
      "FN:Ada Lovelace\r\nN;SCRIPT=Latn:Lovelace;Ada;Byron;Dr;III\r\n" &
      "ORG;SORT-AS=Analytical Engines,Research,Mathematics:Analytical Engines;Research;Mathematics\r\n" &
      "TITLE;TYPE=work:Chief Analyst\r\nROLE;TYPE=work:Project Leader\r\n" &
      "TEL;TYPE=cell,voice:+33123456789\r\nLANG;TYPE=work;PREF=2:en\r\n" &
      "ADR;TYPE=work;SCRIPT=Latn:;Suite 1;Main Street;London;;EC1;UK\r\n" &
      "GEO;TYPE=work:geo:51.5074,-0.1278\r\nTZ;TYPE=work:Europe/London\r\n" &
      "CATEGORIES:math,computing\r\nURL;TYPE=work;MEDIATYPE=text/html;X-TRACE=abc:https://ada.test\r\n" &
      "KIND:individual\r\nPRODID:-//UniDAV//\r\nREV:20260821T120000Z\r\n" &
      "BDAY:18151210\r\nNICKNAME:Ada\r\nMEMBER:urn:uuid:member\r\n" &
      "BIRTHPLACE;VALUE=text:London\r\nDEATHDATE:20991231\r\n" &
      "DEATHPLACE;VALUE=uri:geo:51.5074,-0.1278\r\n" &
      "GRAMGENDER:nonbinary\r\n" &
      "RELATED;TYPE=colleague:urn:uuid:related\r\n" &
      "IMPP;SERVICE-TYPE=Mastodon;USERNAME=@ada:acct:ada@social.example\r\n" &
      "EXPERTISE;LEVEL=high;INDEX=1:mathematics\r\nHOBBY;LEVEL=medium:reading\r\n" &
      "ORG-DIRECTORY;INDEX=2;PREF=1;TYPE=work:https://directory.ada.test\r\n" &
      "SOURCE;MEDIATYPE=text/vcard:https://directory.ada.test/ada.vcf\r\n" &
      "PHOTO;MEDIATYPE=image/jpeg:https://ada.test/photo.jpg\r\n" &
      "KEY;MEDIATYPE=application/pkix:https://ada.test/key\r\n" &
      "CALADRURI;PREF=1:mailto:ada@example.test\r\n" &
      "CALURI;MEDIATYPE=text/calendar:https://ada.test/calendar\r\n" &
      "FBURL;PREF=1;MEDIATYPE=text/calendar:https://ada.test/freebusy\r\n" &
      "END:VCARD\r\n"
    let structuredJs = parseJson(jsContactFromVCard(structured))
    check structuredJs["name"]["components"][1]["kind"].getStr == "given"
    check structuredJs["name"]["phoneticScript"].getStr == "Latn"
    check structuredJs["organizations"]["org0"]["units"][1]["name"].getStr == "Mathematics"
    check structuredJs["organizations"]["org0"]["sortAs"].getStr == "Analytical Engines"
    check structuredJs["organizations"]["org0"]["units"][0]["sortAs"].getStr == "Research"
    check structuredJs["titles"]["title0"]["kind"].getStr == "title"
    check structuredJs["titles"]["title1"]["kind"].getStr == "role"
    check structuredJs["addresses"]["address0"]["contexts"]["work"].getBool
    check structuredJs["addresses"]["address0"]["coordinates"].getStr == "geo:51.5074,-0.1278"
    check structuredJs["addresses"]["address0"]["timeZone"].getStr == "Europe/London"
    check structuredJs["addresses"]["address0"]["phoneticScript"].getStr == "Latn"
    check structuredJs["keywords"]["math"].getBool
    check structuredJs["links"]["link0"]["uri"].getStr == "https://ada.test"
    check structuredJs["links"]["link0"]["vCardParams"]["x-trace"].getStr == "abc"
    check structuredJs["links"]["link0"]["mediaType"].getStr == "text/html"
    check structuredJs["prodId"].getStr == "-//UniDAV//"
    check structuredJs["nicknames"]["nickname0"]["name"].getStr == "Ada"
    check structuredJs["members"]["urn:uuid:member"].getBool
    check structuredJs["relatedTo"]["urn:uuid:related"]["relation"][
        "colleague"].getBool
    check structuredJs["personalInfo"]["expertise0"]["kind"].getStr == "expertise"
    check structuredJs["personalInfo"]["expertise0"]["level"].getStr == "high"
    check structuredJs["personalInfo"]["expertise0"]["listAs"].getInt == 1
    check structuredJs["anniversaries"]["anniversary0"]["kind"].getStr == "birth"
    check structuredJs["anniversaries"]["anniversary0"]["place"][
        "full"].getStr == "London"
    check structuredJs["anniversaries"]["anniversary1"]["kind"].getStr == "death"
    check structuredJs["anniversaries"]["anniversary1"]["place"][
        "coordinates"].getStr == "geo:51.5074,-0.1278"
    check structuredJs["directories"]["org-directory0"]["kind"].getStr == "directory"
    check structuredJs["directories"]["org-directory0"]["listAs"].getInt == 2
    check structuredJs["directories"]["org-directory0"]["pref"].getInt == 1
    check structuredJs["directories"]["source0"]["kind"].getStr == "entry"
    check structuredJs["directories"]["source0"]["mediaType"].getStr == "text/vcard"
    check structuredJs["media"]["photo0"]["kind"].getStr == "photo"
    check structuredJs["media"]["photo0"]["mediaType"].getStr == "image/jpeg"
    check structuredJs["cryptoKeys"]["key0"]["uri"].getStr == "https://ada.test/key"
    check structuredJs["cryptoKeys"]["key0"]["mediaType"].getStr == "application/pkix"
    check structuredJs["phones"]["phone0"]["features"]["cell"].getBool
    check structuredJs["preferredLanguages"]["lang0"]["pref"].getInt == 2
    check structuredJs["speakToAs"]["grammaticalGender"].getStr == "nonbinary"
    check structuredJs["onlineServices"]["os0"]["service"].getStr == "Mastodon"
    check structuredJs["onlineServices"]["os0"]["user"].getStr == "@ada"
    check structuredJs["schedulingAddresses"]["caladruri0"]["pref"].getInt == 1
    check structuredJs["calendars"]["caluri0"]["kind"].getStr == "calendar"
    check structuredJs["calendars"]["caluri0"]["mediaType"].getStr == "text/calendar"
    check structuredJs["calendars"]["fburl0"]["kind"].getStr == "freeBusy"
    let structuredCard = vCardFromJsContact($structuredJs)
    check structuredCard.contains("N;SCRIPT=Latn:Lovelace;Ada;Byron;Dr;III\r\n")
    check structuredCard.contains("ORG;SORT-AS=")
    let restoredOrg = parseComponents(structuredCard)[0].properties("ORG")[0]
    check restoredOrg.value == "Analytical Engines;Research;Mathematics"
    var restoredSortAs: seq[string]
    for parameter in restoredOrg.params:
      if parameter.name == "SORT-AS": restoredSortAs = parameter.values
    check restoredSortAs == @["Analytical Engines", "Research", "Mathematics"]
    check structuredCard.contains("TITLE;TYPE=work:Chief Analyst\r\n")
    check structuredCard.contains("ROLE;TYPE=work:Project Leader\r\n")
    check structuredCard.contains("ADR;TYPE=work;")
    check structuredCard.contains("SCRIPT=Latn")
    check structuredCard.contains("TZ=Europe/London")
    check structuredCard.contains("N;SCRIPT=Latn:Lovelace;Ada;Byron;Dr;III\r\n")
    check structuredCard.contains("GEO;TYPE=work:geo:51.5074,-0.1278\r\n")
    check structuredCard.contains("IMPP;SERVICE-TYPE=Mastodon;USERNAME=@ada:acct:ada@social.example\r\n")
    check structuredCard.contains("CATEGORIES:math,computing\r\n")
    check structuredCard.contains("URL;TYPE=work;")
    check structuredCard.contains("MEDIATYPE=text/html")
    check structuredCard.contains("X-TRACE=abc")
    check structuredCard.contains("BDAY:18151210\r\n")
    check structuredCard.contains("BIRTHPLACE;VALUE=text:London\r\n")
    check structuredCard.contains("DEATHDATE:20991231\r\n")
    check structuredCard.contains("DEATHPLACE;VALUE=uri:geo:51.5074,-0.1278\r\n")
    check structuredCard.contains("NICKNAME:Ada\r\n")
    check structuredCard.contains("MEMBER:urn:uuid:member\r\n")
    check structuredCard.contains("RELATED;TYPE=colleague:urn:uuid:related\r\n")
    check structuredCard.contains("EXPERTISE;LEVEL=high;INDEX=1:mathematics\r\n")
    check structuredCard.contains("HOBBY;LEVEL=medium:reading\r\n")
    check structuredCard.contains("ORG-DIRECTORY;INDEX=2;PREF=1;TYPE=work:https://directory.ada.test\r\n")
    check structuredCard.contains("SOURCE;MEDIATYPE=text/vcard:https://directory.ada.test/ada.vcf\r\n")
    check structuredCard.contains("PHOTO;MEDIATYPE=image/jpeg:https://ada.test/photo.jpg\r\n")
    check structuredCard.contains("KEY;MEDIATYPE=application/pkix:https://ada.test/key\r\n")
    check structuredCard.contains("TEL;TYPE=cell,voice:+33123456789\r\n")
    check structuredCard.contains("LANG;TYPE=work;PREF=2:en\r\n")
    check structuredCard.contains("GRAMGENDER:nonbinary\r\n")
    check structuredCard.contains("CALADRURI;PREF=1:mailto:ada@example.test\r\n")
    check structuredCard.contains("CALURI;MEDIATYPE=text/calendar:https://ada.test/calendar\r\n")
    check structuredCard.contains("FBURL;PREF=1;MEDIATYPE=text/calendar:https://ada.test/freebusy\r\n")

suite "RFC JSON formats":
  test "maps a grouped and structured vCard to RFC 7095 jCard":
    let source = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada Lovelace\r\n" &
      "N:Lovelace;Ada;;;\r\nITEM1.EMAIL;TYPE=work,internet:ada@example.test\r\n" &
      "ADR:;;My Street,Left Side;London;;;UK\r\nX-OPAQUE;X-P=one:alpha\\,beta\r\nEND:VCARD\r\n"
    let card = parseJson(jCardJson(source))
    check card[0].getStr == "vcard"
    check card[1][0] == %*["version", %*{}, "text", "4.0"]
    check card[1][3][1]["group"].getStr == "item1"
    check card[1][3][1]["type"] == %*["work", "internet"]
    check card[1][4][3][2] == %*["My Street", "Left Side"]
    check card[1][5][2].getStr == "unknown"
    let restored = documentFromJCard($card)
    check restored.contains("ITEM1.EMAIL;TYPE=work,internet:ada@example.test")
    check restored.contains("ADR:;;My Street,Left Side;London;;;UK")
    check restored.contains("X-OPAQUE;X-P=one:alpha\\,beta")

  test "maps complete, reduced and truncated RFC 7095 temporal values":
    let source = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Temporal Contact\r\n" &
      "BDAY:19850412\r\nANNIVERSARY:---15T094500+0100\r\n" &
      "REV:20130214T123000Z\r\nX-DATE;VALUE=DATE:--0412\r\n" &
      "X-TIME;VALUE=TIME:-2050-0800\r\nEND:VCARD\r\n"
    let card = parseJson(jCardJson(source))
    check card[1][2] == %*["bday", %*{}, "date-and-or-time", "1985-04-12"]
    check card[1][3] == %*["anniversary", %*{}, "date-and-or-time",
      "---15T09:45:00+01:00"]
    check card[1][4] == %*["rev", %*{}, "timestamp",
      "2013-02-14T12:30:00Z"]
    check card[1][5] == %*["x-date", %*{}, "date", "--04-12"]
    check card[1][6] == %*["x-time", %*{}, "time", "-20:50-08:00"]
    let restored = documentFromJCard($card)
    for expected in ["BDAY:19850412", "ANNIVERSARY:---15T094500+0100",
        "REV:20130214T123000Z", "X-DATE;VALUE=DATE:--0412",
        "X-TIME;VALUE=TIME:-2050-0800"]:
      check restored.contains(expected)

  test "maps nested iCalendar values to RFC 7265 jCal":
    let source = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\n" &
      "BEGIN:VTODO\r\nUID:event-1\r\nDTSTART:20260816T120000Z\r\n" &
      "PERCENT-COMPLETE:42\r\nCATEGORIES:Work,Review\r\n" &
      "X-OPAQUE;X-P=one:alpha\\,beta\r\nDTSTAMP:20260801T120000Z\r\n" &
      "END:VTODO\r\nEND:VCALENDAR\r\n"
    let calendar = parseJson(jCalJson(source))
    check calendar[0].getStr == "vcalendar"
    check calendar[2][0][0].getStr == "vtodo"
    check calendar[2][0][1][1] == %*["dtstart", %*{}, "date-time",
      "2026-08-16T12:00:00Z"]
    check calendar[2][0][1][2][3].getInt == 42
    check calendar[2][0][1][3] == %*["categories", %*{}, "text", "Work",
      "Review"]
    check calendar[2][0][1][4][2].getStr == "unknown"
    let restored = documentFromJCal($calendar)
    check restored.contains("DTSTART:20260816T120000Z")
    check restored.contains("PERCENT-COMPLETE:42")
    check restored.contains("CATEGORIES:Work,Review")
    check restored.contains("X-OPAQUE;X-P=one:alpha\\,beta")

  test "maps specialized recurrence, period and temporal jCal values":
    let source = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\n" &
      "BEGIN:VEVENT\r\nUID:special\r\n" &
      "RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;UNTIL=20260901T120000Z\r\n" &
      "DTSTAMP:20260801T120000Z\r\nEND:VEVENT\r\n" &
      "BEGIN:VFREEBUSY\r\nUID:busy\r\nDTSTAMP:20260801T120000Z\r\n" &
      "FREEBUSY:20260817T090000Z/20260817T100000Z," &
      "20260818T090000Z/PT1H\r\n" &
      "REQUEST-STATUS:2.0;Success\r\n" &
      "X-TIME;VALUE=TIME:123045Z\r\n" &
      "X-OFFSET;VALUE=UTC-OFFSET:+0530\r\nEND:VFREEBUSY\r\n" &
      "END:VCALENDAR\r\n"
    let calendar = parseJson(jCalJson(source))
    let properties = calendar[2][0][1]
    check properties[1][3]["freq"].getStr == "WEEKLY"
    check properties[1][3]["interval"].getInt == 2
    check properties[1][3]["byday"] == %*["MO", "WE"]
    check properties[1][3]["until"].getStr == "2026-09-01T12:00:00Z"
    let busyProperties = calendar[2][1][1]
    check busyProperties[2][3] == %*["2026-08-17T09:00:00Z",
      "2026-08-17T10:00:00Z"]
    check busyProperties[2][4] == %*["2026-08-18T09:00:00Z", "PT1H"]
    check busyProperties[3][3] == %*["2.0", "Success"]
    check busyProperties[4][3].getStr == "12:30:45Z"
    check busyProperties[5][3].getStr == "+05:30"
    let restored = documentFromJCal($calendar)
    check restored.contains("RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;" &
      "UNTIL=20260901T120000Z")
    check restored.contains("FREEBUSY:20260817T090000Z/20260817T100000Z," &
      "20260818T090000Z/PT1H")
    check restored.contains("REQUEST-STATUS:2.0;Success")
    check restored.contains("X-TIME;VALUE=TIME:123045Z")
    check restored.contains("X-OFFSET;VALUE=UTC-OFFSET:+0530")

  test "rejects malformed, mistyped and excessive JSON mappings":
    expect JsonFormatError: discard parseJCard("{}")
    expect JsonFormatError: discard parseJCard("[\"vcard\",[[\"x\",{},\"boolean\",\"TRUE\"]]]")
    expect JsonFormatError: discard parseJCal("[\"vcalendar\",[],{}]")
    expect JsonFormatError:
      discard parseJCard(repeat(" ", MaxJsonBytes + 1))
    expect JsonFormatError:
      discard parseJCard("[\"vcard\",[[\"x\",{\"p\":[1]},\"text\",\"v\"]]]")
    expect JsonFormatError:
      discard parseJCal("[\"vcalendar\",[[\"version\",{},\"text\",\"2.0\"]," &
        "[\"prodid\",{},\"text\",\"x\"]],[[\"vevent\",[[\"uid\",{}," &
        "\"text\",\"1\"],[\"rrule\",{},\"recur\",{}]],[]]]]")

suite "three-way lossless merges":
  test "merges independent property edits and keeps extensions":
    let base = "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:urn:uuid:ada\r\nFN:Ada\r\n" &
      "EMAIL:ada@example.test\r\nX-KEEP:opaque\r\nEND:VCARD\r\n"
    let local = base.replace("FN:Ada", "FN:Grace")
    let remote = base.replace("EMAIL:ada@example.test", "EMAIL:ada@new.test")
    let merged = mergeThreeWay(base, local, remote)
    check merged.conflicts.len == 0
    check merged.document.contains("FN:Grace")
    check merged.document.contains("EMAIL:ada@new.test")
    check merged.document.contains("X-KEEP:opaque")

  test "reports same-field conflicts without overwriting base":
    let base = "BEGIN:VCARD\r\nVERSION:4.0\r\nUID:urn:uuid:ada\r\nFN:Ada\r\nEND:VCARD\r\n"
    let merged = mergeThreeWay(base, base.replace("FN:Ada", "FN:Grace"),
      base.replace("FN:Ada", "FN:Lin"))
    check merged.conflicts.len == 1
    check merged.conflicts[0].property == "FN"
    check merged.document.contains("FN:Ada")

suite "what the review found":
  # Each of these was measured on the code before it was changed, not inferred.

  test "a carriage return is escaped, not left to end the line":
    # Raw, it terminates the content line mid-value and the rest is read as a
    # new property.
    check textEscape("a\r\nb") == "a\\nb"
    check textEscape("a\rb") == "a\\nb"
    check textEscape("a\nb") == "a\\nb"

  test "propfind refuses a namespace its body cannot declare":
    expect DavXmlError:
      discard propfindBody([("http://example.org/ns", "thing")])
    # The three it declares still work.
    check "D:getetag" in propfindBody([(DavNamespace, "getetag")])
    check "C:calendar-data" in propfindBody([(CalDavNamespace,
        "calendar-data")])

  test "propfind refuses a property name that is markup":
    for name in ["a b", "a<b", "a\"b", ""]:
      expect DavXmlError:
        discard propfindBody([(DavNamespace, name)])

  test "an alarm with two faults reports both":
    # The ACTION check used to hang off the TRIGGER count, so only one showed.
    let alarm = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//T//EN\r\n" &
      "BEGIN:VEVENT\r\nUID:a\r\nDTSTAMP:20260101T000000Z\r\n" &
      "DTSTART:20260101T000000Z\r\nBEGIN:VALARM\r\nACTION:NONSENSE\r\n" &
      "END:VALARM\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
    let report = validationJson(alarm)
    check "exactly one TRIGGER" in report
    check "ACTION is not an RFC 5545 value" in report
