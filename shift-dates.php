<?php

/**
 * Shifts every date in the database forward so the dataset describes "now".
 *
 * A generated dump is a snapshot of the moment it was built. Days later its
 * allocations have timed out, its upcoming events are in the past, and nothing
 * is left for a psychologist to confirm. Shifting moves the whole dataset by a
 * single delta, so every relative distance between rows is preserved -- a
 * beneficiary allocated three hours before the snapshot is still allocated
 * three hours ago afterwards.
 *
 * The anchor is `settings.test_dataset_generated_at`, written by
 * generate-test-data.php. Without it the newest created_at/updated_at in the
 * database is used instead. Anchoring on those columns matters: plenty of other
 * columns (slot start times, plan expiry) are legitimately in the future and
 * would produce a backwards shift.
 *
 * Running it twice is safe. The anchor is rewritten after each shift, so a
 * second run only advances the data by the time that has since elapsed.
 *
 * Usage:
 *   php shift-dates.php --host=127.0.0.1 --db=bluemonday --user=root --pass=secret [--dry-run]
 */

declare(strict_types=1);

$options = getopt('', ['host:', 'port::', 'db:', 'user:', 'pass:', 'dry-run::', 'min-seconds::']);
foreach (['host', 'db', 'user'] as $required) {
    if (!isset($options[$required])) {
        fwrite(STDERR, "Missing --{$required}\n");
        exit(1);
    }
}

$dryRun = isset($options['dry-run']);
// Below this the shift is not worth the write traffic.
$minimumSeconds = (int) ($options['min-seconds'] ?? 60);

$pdo = new PDO(
    sprintf('mysql:host=%s;port=%s;dbname=%s;charset=utf8mb4', $options['host'], $options['port'] ?? '3306', $options['db']),
    $options['user'],
    $options['pass'] ?? '',
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
);

// Session state is not part of the dataset and shifting it would only produce
// logins that look like they happened in the future.
const SKIPPED_TABLES = ['migrations', 'sessions', 'password_resets', 'failed_jobs', 'personal_access_tokens'];

// ------------------------------------------------------------- find anchor ---

$anchor = null;
$anchorSource = '';

$marker = $pdo->query("SELECT value FROM settings WHERE `key` = 'test_dataset_generated_at'")->fetchColumn();

if ($marker !== false && $marker !== null && strtotime((string) $marker) !== false) {
    $anchor = strtotime((string) $marker);
    $anchorSource = 'settings.test_dataset_generated_at';
}

$dateColumns = [];
$tables = $pdo->query('SHOW TABLES')->fetchAll(PDO::FETCH_COLUMN);

foreach ($tables as $table) {
    if (in_array($table, SKIPPED_TABLES, true)) {
        continue;
    }

    foreach ($pdo->query("SHOW COLUMNS FROM `{$table}`") as $column) {
        if (preg_match('/^(date|datetime|timestamp)/i', $column['Type'])) {
            $dateColumns[$table][] = $column['Field'];
        }
    }
}

if ($anchor === null) {
    $newest = null;

    foreach ($dateColumns as $table => $columns) {
        foreach (array_intersect($columns, ['created_at', 'updated_at']) as $column) {
            $value = $pdo->query("SELECT MAX(`{$column}`) FROM `{$table}`")->fetchColumn();

            if ($value !== false && $value !== null) {
                $newest = max($newest ?? 0, (int) strtotime((string) $value));
            }
        }
    }

    if ($newest === null) {
        fwrite(STDERR, "No anchor found: the database has no timestamps to shift.\n");
        exit(1);
    }

    $anchor = $newest;
    $anchorSource = 'newest created_at/updated_at';
}

$now = time();
$delta = $now - $anchor;

printf("Anchor:  %s (%s)\n", date('Y-m-d H:i:s', $anchor), $anchorSource);
printf("Target:  %s\n", date('Y-m-d H:i:s', $now));
printf("Shift:   %+d seconds (%+.1f days)\n\n", $delta, $delta / 86400);

if ($delta === 0 || abs($delta) < $minimumSeconds) {
    echo "Dataset is already current; nothing to shift.\n";
    exit(0);
}

if ($dryRun) {
    foreach ($dateColumns as $table => $columns) {
        printf("  %-42s %s\n", $table, implode(', ', $columns));
    }
    printf("\nDry run: %d tables would be shifted.\n", count($dateColumns));
    exit(0);
}

// ------------------------------------------------------------------ shift ---

// All of a table's date columns move in one statement: fewer row rewrites, and
// no chance of a partially shifted row.
$pdo->exec('SET FOREIGN_KEY_CHECKS=0');

$shiftedTables = 0;
$shiftedRows = 0;

foreach ($dateColumns as $table => $columns) {
    $assignments = [];

    foreach ($columns as $column) {
        $assignments[] = sprintf(
            '`%s` = DATE_ADD(`%s`, INTERVAL %d SECOND)',
            $column,
            $column,
            $delta
        );
    }

    $conditions = array_map(fn ($column) => "`{$column}` IS NOT NULL", $columns);

    $sql = sprintf(
        'UPDATE `%s` SET %s WHERE %s',
        $table,
        implode(', ', $assignments),
        implode(' OR ', $conditions)
    );

    $affected = $pdo->exec($sql);

    if ($affected > 0) {
        $shiftedTables++;
        $shiftedRows += $affected;
        printf("  %-42s %6d rows\n", $table, $affected);
    }
}

$pdo->exec('SET FOREIGN_KEY_CHECKS=1');

// Move the anchor with the data so a later run shifts only the elapsed time.
$update = $pdo->prepare("UPDATE settings SET value = ?, updated_at = ? WHERE `key` = 'test_dataset_generated_at'");
$update->execute([date('Y-m-d H:i:s', $now), date('Y-m-d H:i:s', $now)]);

if ($update->rowCount() === 0) {
    $pdo->prepare("INSERT INTO settings (`key`, value, data_type, created_at, updated_at) VALUES ('test_dataset_generated_at', ?, 'text', ?, ?)")
        ->execute([date('Y-m-d H:i:s', $now), date('Y-m-d H:i:s', $now)]);
}

printf("\nShifted %d rows across %d tables.\n", $shiftedRows, $shiftedTables);

// ------------------------------------------------------------- what it did ---

$timeoutDays = (int) ($pdo->query("SELECT value FROM settings WHERE `key` = 'client_allocation_timeout_days'")->fetchColumn() ?: 2);

$confirmable = $pdo->query("
    SELECT COUNT(*) AS clients, COUNT(DISTINCT psiholog_id) AS psychologists
    FROM clients
    WHERE psiholog_id IS NOT NULL
      AND selected_slot_id IS NOT NULL
      AND slot_confirmed = 0
      AND appointment_rejected_at IS NULL
      AND psiholog_allocated_at IS NOT NULL
      AND psiholog_allocated_at > DATE_SUB(NOW(), INTERVAL {$timeoutDays} DAY)
")->fetch(PDO::FETCH_ASSOC);

printf(
    "Awaiting confirmation and still inside the %d-day window: %d beneficiaries across %d psychologists.\n",
    $timeoutDays,
    $confirmable['clients'],
    $confirmable['psychologists']
);
