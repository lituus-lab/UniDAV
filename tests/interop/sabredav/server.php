<?php
declare(strict_types=1);

error_reporting(E_ALL & ~E_DEPRECATED & ~E_NOTICE);
date_default_timezone_set('UTC');
require '/app/vendor/autoload.php';

$database = getenv('SABREDAV_DB') ?: '/data/db.sqlite';
$pdo = new PDO('sqlite:' . $database);
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

$auth = new class extends Sabre\DAV\Auth\Backend\AbstractBasic {
    protected function validateUserPass($username, $password) {
        return hash_equals('admin', (string) $username) && hash_equals('admin', (string) $password);
    }
};
$auth->setRealm('SabreDAV');
$principals = new Sabre\DAVACL\PrincipalBackend\PDO($pdo);
$calendars = new Sabre\CalDAV\Backend\PDO($pdo);
$addressBooks = new Sabre\CardDAV\Backend\PDO($pdo);

$server = new Sabre\DAV\Server([
    new Sabre\CalDAV\Principal\Collection($principals),
    new Sabre\CalDAV\CalendarRoot($principals, $calendars),
    new Sabre\CardDAV\AddressBookRoot($principals, $addressBooks),
]);
$server->setBaseUri('/');
$server->addPlugin(new Sabre\DAV\Auth\Plugin($auth));
$server->addPlugin(new Sabre\DAV\Sync\Plugin());
$server->addPlugin(new Sabre\DAVACL\Plugin());
$server->addPlugin(new Sabre\CalDAV\Plugin());
$server->addPlugin(new Sabre\CardDAV\Plugin());
$server->start();
