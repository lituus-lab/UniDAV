<?php
declare(strict_types=1);

require '/app/vendor/autoload.php';
$database = getenv('SABREDAV_DB') ?: '/data/db.sqlite';
$pdo = new PDO('sqlite:' . $database);
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

$schema = <<<'SQL'
CREATE TABLE users (id INTEGER PRIMARY KEY ASC NOT NULL, username TEXT NOT NULL,
  digesta1 TEXT NOT NULL, UNIQUE(username));
CREATE TABLE principals (id INTEGER PRIMARY KEY ASC NOT NULL, uri TEXT NOT NULL,
  email TEXT, displayname TEXT, UNIQUE(uri));
CREATE TABLE groupmembers (id INTEGER PRIMARY KEY ASC NOT NULL, principal_id INTEGER NOT NULL,
  member_id INTEGER NOT NULL, UNIQUE(principal_id, member_id));
CREATE TABLE calendarobjects (id INTEGER PRIMARY KEY ASC NOT NULL, calendardata BLOB NOT NULL,
  uri TEXT NOT NULL, calendarid INTEGER NOT NULL, lastmodified INTEGER NOT NULL, etag TEXT NOT NULL,
  size INTEGER NOT NULL, componenttype TEXT, firstoccurence INTEGER, lastoccurence INTEGER, uid TEXT,
  UNIQUE(calendarid, uri));
CREATE INDEX calendarid_time ON calendarobjects (calendarid, firstoccurence);
CREATE TABLE calendars (id INTEGER PRIMARY KEY ASC NOT NULL, synctoken INTEGER DEFAULT 1 NOT NULL,
  components TEXT NOT NULL);
CREATE TABLE calendarinstances (id INTEGER PRIMARY KEY ASC NOT NULL, calendarid INTEGER NOT NULL,
  principaluri TEXT NULL, access INTEGER NOT NULL DEFAULT 1, displayname TEXT, uri TEXT NOT NULL,
  description TEXT, calendarorder INTEGER, calendarcolor TEXT, timezone TEXT, transparent BOOL,
  share_href TEXT, share_displayname TEXT, share_invitestatus INTEGER DEFAULT 2,
  UNIQUE(principaluri, uri), UNIQUE(calendarid, principaluri), UNIQUE(calendarid, share_href));
CREATE TABLE calendarchanges (id INTEGER PRIMARY KEY ASC NOT NULL, uri TEXT, synctoken INTEGER NOT NULL,
  calendarid INTEGER NOT NULL, operation INTEGER NOT NULL);
CREATE INDEX calendarid_synctoken ON calendarchanges (calendarid, synctoken);
CREATE TABLE calendarsubscriptions (id INTEGER PRIMARY KEY ASC NOT NULL, uri TEXT NOT NULL,
  principaluri TEXT NOT NULL, source TEXT NOT NULL, displayname TEXT, refreshrate TEXT,
  calendarorder INTEGER, calendarcolor TEXT, striptodos BOOL, stripalarms BOOL, stripattachments BOOL,
  lastmodified INTEGER, UNIQUE(principaluri, uri));
CREATE TABLE schedulingobjects (id INTEGER PRIMARY KEY ASC NOT NULL, principaluri TEXT NOT NULL,
  calendardata BLOB, uri TEXT NOT NULL, lastmodified INTEGER, etag TEXT NOT NULL, size INTEGER NOT NULL,
  UNIQUE(principaluri, uri));
CREATE TABLE addressbooks (id INTEGER PRIMARY KEY ASC NOT NULL, principaluri TEXT NOT NULL,
  displayname TEXT, uri TEXT NOT NULL, description TEXT, synctoken INTEGER DEFAULT 1 NOT NULL,
  UNIQUE(principaluri, uri));
CREATE TABLE cards (id INTEGER PRIMARY KEY ASC NOT NULL, addressbookid INTEGER NOT NULL,
  carddata BLOB, uri TEXT NOT NULL, lastmodified INTEGER, etag TEXT, size INTEGER,
  UNIQUE(addressbookid, uri));
CREATE TABLE addressbookchanges (id INTEGER PRIMARY KEY ASC NOT NULL, uri TEXT,
  synctoken INTEGER NOT NULL, addressbookid INTEGER NOT NULL, operation INTEGER NOT NULL);
CREATE INDEX addressbookid_synctoken ON addressbookchanges (addressbookid, synctoken);
SQL;

$pdo->exec($schema);
$digest = md5('admin:SabreDAV:admin');
$statement = $pdo->prepare('INSERT INTO users (username, digesta1) VALUES (?, ?)');
$statement->execute(['admin', $digest]);
$pdo->exec("INSERT INTO principals (uri,email,displayname) VALUES
  ('principals/admin','admin@example.test','Interop Administrator'),
  ('principals/admin/calendar-proxy-read',NULL,NULL),
  ('principals/admin/calendar-proxy-write',NULL,NULL)");

$calendarBackend = new Sabre\CalDAV\Backend\PDO($pdo);
$calendarBackend->createCalendar('principals/admin', 'interop-calendar', [
    '{DAV:}displayname' => 'Interop Calendar',
]);
$addressBookBackend = new Sabre\CardDAV\Backend\PDO($pdo);
$addressBookBackend->createAddressBook('principals/admin', 'interop-addressbook', [
    '{DAV:}displayname' => 'Interop Address Book',
]);

echo "SabreDAV fixture initialized\n";
