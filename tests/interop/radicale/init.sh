#!/bin/sh
set -eu

rm -rf /tmp/data
mkdir -p /tmp/data/collections
printf '%s\n' 'interop:interop-password' > /tmp/data/users
chmod 600 /tmp/data/users
mkdir -p /tmp/data/collections/collection-root/interop/calendar
mkdir -p /tmp/data/collections/collection-root/interop/addressbook
printf '%s' '{"tag":"VCALENDAR","D:displayname":"Interop Calendar"}' > /tmp/data/collections/collection-root/interop/calendar/.Radicale.props
printf '%s' '{"tag":"VADDRESSBOOK","D:displayname":"Interop Address Book"}' > /tmp/data/collections/collection-root/interop/addressbook/.Radicale.props

cat > /tmp/event.ics <<'ICS'
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:radicale-seed
DTSTAMP:20260801T120000Z
DTSTART:20260801T100000Z
DTEND:20260801T110000Z
END:VEVENT
END:VCALENDAR
ICS
cat > /tmp/contact.vcf <<'VCF'
BEGIN:VCARD
VERSION:4.0
UID:radicale-seed
FN:Radicale Seed
END:VCARD
VCF

/app/bin/python -m radicale --config /tmp/config >/tmp/radicale.log 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT
until [ "$(curl -sS -o /dev/null -w '%{http_code}' -u interop:interop-password http://127.0.0.1:5232/interop/ || true)" != 000 ]; do
  sleep 1
done
curl -fsS -u interop:interop-password -X PUT -H 'Content-Type: text/calendar' --data-binary @/tmp/event.ics http://127.0.0.1:5232/interop/calendar/seed.ics
curl -fsS -u interop:interop-password -X PUT -H 'Content-Type: text/vcard' --data-binary @/tmp/contact.vcf http://127.0.0.1:5232/interop/addressbook/seed.vcf
wait "$server_pid"
