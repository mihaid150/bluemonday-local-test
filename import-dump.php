<?php

/**
 * Imports a SQL dump produced by export-dump.php.
 *
 * Uses PDO instead of the mysql client so the import works from any container
 * with PHP, and reports a per-table summary plus a foreign key integrity check
 * so a broken dump fails loudly instead of silently importing half the data.
 *
 * Usage:
 *   php import-dump.php --host=127.0.0.1 --db=bluemonday --user=root --pass=secret --file=dump.sql
 */

declare(strict_types=1);

$options = getopt('', ['host:', 'port::', 'db:', 'user:', 'pass:', 'file:', 'quiet::']);
foreach (['host', 'db', 'user', 'file'] as $required) {
    if (!isset($options[$required])) {
        fwrite(STDERR, "Missing --{$required}\n");
        exit(1);
    }
}

if (!is_readable($options['file'])) {
    fwrite(STDERR, "Cannot read {$options['file']}\n");
    exit(1);
}

$quiet = isset($options['quiet']);

$pdo = new PDO(
    sprintf('mysql:host=%s;port=%s;dbname=%s;charset=utf8mb4', $options['host'], $options['port'] ?? '3306', $options['db']),
    $options['user'],
    $options['pass'] ?? '',
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
);

$sql = file_get_contents($options['file']);

if ($sql === false) {
    fwrite(STDERR, "Failed to read dump\n");
    exit(1);
}

/**
 * Split on semicolons that terminate a statement, tracking quoting so a
 * semicolon inside a string literal never ends a statement early.
 */
function statements(string $sql): Generator
{
    $length = strlen($sql);
    $buffer = '';
    $inSingle = false;
    $inDouble = false;
    $inBacktick = false;
    $inLineComment = false;

    for ($i = 0; $i < $length; $i++) {
        $char = $sql[$i];

        if ($inLineComment) {
            if ($char === "\n") {
                $inLineComment = false;
            }
            continue;
        }

        if (!$inSingle && !$inDouble && !$inBacktick) {
            // `-- ` line comments only, which is all export-dump.php emits.
            if ($char === '-' && $i + 1 < $length && $sql[$i + 1] === '-' && ($buffer === '' || substr($buffer, -1) === "\n")) {
                $inLineComment = true;
                continue;
            }
        }

        if ($char === '\\' && ($inSingle || $inDouble)) {
            // Escape sequence: copy this char and the next one verbatim.
            $buffer .= $char;
            if ($i + 1 < $length) {
                $buffer .= $sql[++$i];
            }
            continue;
        }

        if ($char === "'" && !$inDouble && !$inBacktick) {
            $inSingle = !$inSingle;
        } elseif ($char === '"' && !$inSingle && !$inBacktick) {
            $inDouble = !$inDouble;
        } elseif ($char === '`' && !$inSingle && !$inDouble) {
            $inBacktick = !$inBacktick;
        } elseif ($char === ';' && !$inSingle && !$inDouble && !$inBacktick) {
            $statement = trim($buffer);
            if ($statement !== '') {
                yield $statement;
            }
            $buffer = '';
            continue;
        }

        $buffer .= $char;
    }

    $statement = trim($buffer);
    if ($statement !== '') {
        yield $statement;
    }
}

$executed = 0;
foreach (statements($sql) as $statement) {
    try {
        $pdo->exec($statement);
        $executed++;
    } catch (PDOException $exception) {
        fwrite(STDERR, "Failed statement #".($executed + 1).": ".substr($statement, 0, 160)."\n");
        fwrite(STDERR, $exception->getMessage()."\n");
        exit(1);
    }
}

// Constraints were disabled inside the dump; make sure it left a consistent
// database behind rather than trusting the import blindly.
$pdo->exec('SET FOREIGN_KEY_CHECKS=1');

$constraints = $pdo->query("
    SELECT TABLE_NAME, COLUMN_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME
    FROM information_schema.KEY_COLUMN_USAGE
    WHERE TABLE_SCHEMA = DATABASE() AND REFERENCED_TABLE_NAME IS NOT NULL
")->fetchAll(PDO::FETCH_ASSOC);

$orphans = [];
foreach ($constraints as $constraint) {
    $count = (int) $pdo->query(sprintf(
        'SELECT COUNT(*) FROM `%s` c LEFT JOIN `%s` p ON c.`%s` = p.`%s` WHERE c.`%s` IS NOT NULL AND p.`%s` IS NULL',
        $constraint['TABLE_NAME'],
        $constraint['REFERENCED_TABLE_NAME'],
        $constraint['COLUMN_NAME'],
        $constraint['REFERENCED_COLUMN_NAME'],
        $constraint['COLUMN_NAME'],
        $constraint['REFERENCED_COLUMN_NAME']
    ))->fetchColumn();

    if ($count > 0) {
        $orphans[] = sprintf('%s.%s -> %s (%d)', $constraint['TABLE_NAME'], $constraint['COLUMN_NAME'], $constraint['REFERENCED_TABLE_NAME'], $count);
    }
}

$total = 0;
$summary = [];
foreach ($pdo->query('SHOW TABLES')->fetchAll(PDO::FETCH_COLUMN) as $table) {
    $count = (int) $pdo->query("SELECT COUNT(*) FROM `{$table}`")->fetchColumn();
    $summary[$table] = $count;
    $total += $count;
}

if (!$quiet) {
    foreach ($summary as $table => $count) {
        printf("  %-42s %6d\n", $table, $count);
    }
    echo "\n";
}

printf("Executed %d statements; %d tables, %d rows.\n", $executed, count($summary), $total);
printf("Verified %d foreign key constraints.\n", count($constraints));

if ($orphans !== []) {
    echo "ORPHANED REFERENCES:\n";
    foreach ($orphans as $orphan) {
        echo '  '.$orphan."\n";
    }
    exit(1);
}

echo "Import OK: no orphaned references.\n";
