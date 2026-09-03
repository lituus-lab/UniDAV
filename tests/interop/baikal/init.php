<?php
declare(strict_types=1);

$db = '/var/www/baikal/Specific/db/db.sqlite';
$schema = '/var/www/baikal/Core/Resources/Db/SQLite/db.sql';
$pdo = new PDO('sqlite:' . $db);
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$pdo->exec(file_get_contents($schema));

$pdo->beginTransaction();
$pdo->prepare('INSERT INTO users (username, digesta1) VALUES (?, ?)')
    ->execute(['interop', md5('interop:BaikalDAV:interop-password')]);
$pdo->prepare('INSERT INTO principals (uri, email, displayname) VALUES (?, ?, ?)')
    ->execute(['principals/interop', 'interop@example.test', 'UniDAV Interop']);
$pdo->exec("INSERT INTO calendars (synctoken, components) VALUES (1, 'VEVENT,VTODO,VJOURNAL')");
$calendarId = (int) $pdo->lastInsertId();
$pdo->prepare('INSERT INTO calendarinstances (calendarid, principaluri, access, displayname, uri) VALUES (?, ?, 1, ?, ?)')
    ->execute([$calendarId, 'principals/interop', 'Interop Calendar', 'interop-calendar']);
$pdo->prepare('INSERT INTO addressbooks (principaluri, displayname, uri, synctoken) VALUES (?, ?, ?, 1)')
    ->execute(['principals/interop', 'Interop Address Book', 'interop-addressbook']);
$pdo->commit();

$config = "system:\n" .
    "  configured_version: '0.10.1'\n" .
    "  timezone: UTC\n" .
    "  card_enabled: true\n" .
    "  cal_enabled: true\n" .
    "  dav_auth_type: Basic\n" .
    "  admin_passwordhash: '" . hash('sha256', 'admin:BaikalDAV:admin') . "'\n" .
    "  auth_realm: BaikalDAV\n" .
    "  base_uri: '/'\n" .
    "database:\n" .
    "  backend: sqlite\n" .
    "  sqlite_file: '/var/www/baikal/Specific/db/db.sqlite'\n";
file_put_contents('/var/www/baikal/config/baikal.yaml', $config);
chmod($db, 0666);
chmod('/var/www/baikal/config/baikal.yaml', 0666);
echo "Baikal fixture initialized\n";
