#!/usr/bin/env bash
set -Eeuo pipefail

# Run with no arguments and no environment setup:
#
#   bash provision-private-environment.sh
#
# The private directory defaults to the one holding this script, which is where
# the SQL/CSV files and .bluemonday-private.env live, so the script works from
# any working directory. Secrets are loaded from PRIVATE_ENV_FILE (default:
# .bluemonday-private.env in that private directory). PRIVATE_DIR and
# PRIVATE_ENV_FILE can still be overridden, and already-exported variables
# remain supported.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PRIVATE_DIR="${PRIVATE_DIR:-$SCRIPT_DIR}"
PRIVATE_ENV_FILE="${PRIVATE_ENV_FILE:-$PRIVATE_DIR/.bluemonday-private.env}"

if [[ -f "$PRIVATE_ENV_FILE" ]]; then
  # Variables already exported by the caller win over the file, so a one-off
  # `FORCE_IMPORT=1 ./provision-private-environment.sh` is not silently
  # discarded by an assignment inside the env file.
  preset_environment="$(export -p)"

  # This file is owned and maintained by the operator outside the repository.
  # shellcheck disable=SC1090
  set -a
  source "$PRIVATE_ENV_FILE"
  set +a

  eval "$preset_environment" 2>/dev/null || true
  unset preset_environment
fi

PROJECT_DIR="${PROJECT_DIR:-$(cd -- "$SCRIPT_DIR/.." && pwd)}"

DB_CONTAINER="${DB_CONTAINER:-bm-temp-db}"
APP_CONTAINER="${APP_CONTAINER:-bm-temp-app}"
NETWORK_NAME="${NETWORK_NAME:-bm-private-import}"
DB_VOLUME="${DB_VOLUME:-bm-temp-db-data}"
IMAGE_NAME="${IMAGE_NAME:-mipeda150/bluemonday-private:latest}"
IMAGE_SOURCE="${IMAGE_SOURCE:-pull}"
IMAGE_WORKFLOW_PROMPT="${IMAGE_WORKFLOW_PROMPT:-true}"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
DB_NAME="${DB_NAME:-bluemonday}"
DB_USER="${DB_USER:-bluemonday}"
APP_PORT="${APP_PORT:-8083}"
APP_URL="${APP_URL:-http://localhost:${APP_PORT}}"
APP_ENV="${APP_ENV:-local}"
APP_DEBUG="${APP_DEBUG:-false}"
SIRUTA_FILE="${SIRUTA_FILE:-siruta_s1_2025.csv}"
CLIENTS_FILE="${CLIENTS_FILE:-clients.csv}"
PSIHOLOGI_FILE="${PSIHOLOGI_FILE:-psihologi.csv}"
DUMP_FILE="${DUMP_FILE:-}"
# How DUMP_FILE should be loaded:
#   production - legacy dump restored side-by-side, then known tables are
#                copied into the current schema (import:production-sql).
#   raw        - self-contained dump (schema + data + migration state) applied
#                directly, as produced by database/testing/export-dump.php.
DUMP_IMPORT_MODE="${DUMP_IMPORT_MODE:-production}"
# PHP importer shipped next to a raw dump; avoids needing a mysql client.
DUMP_IMPORTER="${DUMP_IMPORTER:-import-dump.php}"
# PROD or TEST. Only a TEST environment may have its dates rewritten; on PROD
# the date-shift step is never offered and never runs.
ENVIRONMENT_TYPE="${ENVIRONMENT_TYPE:-PROD}"
# ask | yes | no. "ask" prompts on a TEST environment with a terminal attached,
# and falls back to "no" when running unattended.
SHIFT_DATES="${SHIFT_DATES:-ask}"
SHIFT_DATES_SCRIPT="${SHIFT_DATES_SCRIPT:-shift-dates.php}"
FORCE_IMPORT="${FORCE_IMPORT:-0}"
MAIL_MAILER="${MAIL_MAILER:-log}"
QUEUE_CONNECTION="${QUEUE_CONNECTION:-sync}"
BROADCAST_DRIVER="${BROADCAST_DRIVER:-null}"
CACHE_DRIVER="${CACHE_DRIVER:-file}"
FILESYSTEM_DRIVER="${FILESYSTEM_DRIVER:-local}"
REDIS_CONTAINER="${REDIS_CONTAINER:-bm-temp-redis}"
MINIO_CONTAINER="${MINIO_CONTAINER:-bm-temp-minio}"
CLAMAV_CONTAINER="${CLAMAV_CONTAINER:-bm-temp-clamav}"
REDIS_CLIENT="${REDIS_CLIENT:-phpredis}"
REDIS_HOST="${REDIS_HOST:-$REDIS_CONTAINER}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"
MIX_ECHO_ENABLED="${MIX_ECHO_ENABLED:-false}"
MIX_ECHO_HOST="${MIX_ECHO_HOST:-}"
MESSAGE_PAGE_SIZE="${MESSAGE_PAGE_SIZE:-30}"
MESSAGE_MAX_ATTACHMENT_KB="${MESSAGE_MAX_ATTACHMENT_KB:-10240}"
MESSAGE_FILESYSTEM_DISK="${MESSAGE_FILESYSTEM_DISK:-local}"
MESSAGE_RETENTION_DAYS="${MESSAGE_RETENTION_DAYS:-730}"
MESSAGE_ANTIVIRUS_ENABLED="${MESSAGE_ANTIVIRUS_ENABLED:-false}"
MESSAGE_ALLOW_WITHOUT_ANTIVIRUS="${MESSAGE_ALLOW_WITHOUT_ANTIVIRUS:-false}"
CLAMAV_HOST="${CLAMAV_HOST:-$CLAMAV_CONTAINER}"
CLAMAV_PORT="${CLAMAV_PORT:-3310}"
CLAMAV_TIMEOUT="${CLAMAV_TIMEOUT:-120}"
# Backing services provisioned by this script when the configuration enables
# them. Images, volumes and health budgets stay overridable from the env file.
REDIS_IMAGE="${REDIS_IMAGE:-redis:7-alpine}"
REDIS_VOLUME="${REDIS_VOLUME:-bm-temp-redis-data}"
MINIO_IMAGE="${MINIO_IMAGE:-minio/minio:latest}"
MINIO_MC_IMAGE="${MINIO_MC_IMAGE:-minio/mc:latest}"
MINIO_VOLUME="${MINIO_VOLUME:-bm-temp-minio-data}"
MINIO_ROOT_USER="${MINIO_ROOT_USER:-}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-}"
MINIO_BUCKET="${MINIO_BUCKET:-${AWS_BUCKET:-}}"
MINIO_API_PORT="${MINIO_API_PORT:-9000}"
MINIO_CONSOLE_PORT="${MINIO_CONSOLE_PORT:-9001}"
CLAMAV_IMAGE="${CLAMAV_IMAGE:-clamav/clamav:latest}"
CLAMAV_VOLUME="${CLAMAV_VOLUME:-bm-temp-clamav-data}"
# The official ClamAV image does not always publish an arm64 manifest.
CLAMAV_PLATFORM="${CLAMAV_PLATFORM:-}"
SERVICE_HEALTH_TIMEOUT="${SERVICE_HEALTH_TIMEOUT:-180}"
# First boot downloads the full virus database, which is far slower than the
# other services.
CLAMAV_HEALTH_TIMEOUT="${CLAMAV_HEALTH_TIMEOUT:-600}"
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
AWS_BUCKET="${AWS_BUCKET:-}"
AWS_ENDPOINT="${AWS_ENDPOINT:-http://${MINIO_CONTAINER}:9000}"
AWS_USE_PATH_STYLE_ENDPOINT="${AWS_USE_PATH_STYLE_ENDPOINT:-false}"
WORKER_CONTAINER="${WORKER_CONTAINER:-bm-temp-worker}"
SCHEDULER_CONTAINER="${SCHEDULER_CONTAINER:-bm-temp-scheduler}"
ECHO_ENABLED="${ECHO_ENABLED:-false}"
ECHO_CONTAINER="${ECHO_CONTAINER:-bm-temp-echo}"
ECHO_IMAGE="${ECHO_IMAGE:-bluemonday-echo:latest}"
ECHO_PORT="${ECHO_PORT:-6001}"
MAIL_LOG_CHANNEL="${MAIL_LOG_CHANNEL:-mail}"
MAIL_FROM_ADDRESS="${MAIL_FROM_ADDRESS:-no-reply@bluemonday.test}"
MAIL_FROM_NAME="${MAIL_FROM_NAME:-Blue Monday}"
MAIL_HOST="${MAIL_HOST:-}"
MAIL_PORT="${MAIL_PORT:-587}"
MAIL_USERNAME="${MAIL_USERNAME:-}"
MAIL_PASSWORD="${MAIL_PASSWORD:-}"
MAIL_ENCRYPTION="${MAIL_ENCRYPTION:-tls}"

# Docker's `-e NAME` form forwards values without exposing secret values in
# the process arguments. Ensure defaults and values loaded above are exported.
export APP_URL APP_KEY APP_ENV APP_DEBUG DB_PASSWORD QUEUE_CONNECTION BROADCAST_DRIVER CACHE_DRIVER FILESYSTEM_DRIVER
export REDIS_CLIENT REDIS_HOST REDIS_PORT REDIS_PASSWORD
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION AWS_BUCKET AWS_ENDPOINT AWS_USE_PATH_STYLE_ENDPOINT
export MESSAGE_PAGE_SIZE MESSAGE_MAX_ATTACHMENT_KB MESSAGE_FILESYSTEM_DISK MESSAGE_RETENTION_DAYS
export MESSAGE_ANTIVIRUS_ENABLED MESSAGE_ALLOW_WITHOUT_ANTIVIRUS CLAMAV_HOST CLAMAV_PORT CLAMAV_TIMEOUT
export MINIO_ROOT_USER MINIO_ROOT_PASSWORD MINIO_BUCKET

log() { printf '\n[%s] %s\n' "$(date +'%H:%M:%S')" "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
require_env() {
  [[ -n "${!1:-}" ]] || die "Set $1 in $PRIVATE_ENV_FILE or export it before running this script."
}
exists_container() { docker container inspect "$1" >/dev/null 2>&1; }
running_container() { [[ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null || true)" == "true" ]]; }
ensure_volume() { docker volume inspect "$1" >/dev/null 2>&1 || docker volume create "$1" >/dev/null; }

# Which backing services the current configuration requires.
redis_enabled() {
  [[ "$QUEUE_CONNECTION" == "redis" || "$CACHE_DRIVER" == "redis" \
    || "$BROADCAST_DRIVER" == "redis" || "$ECHO_ENABLED" == "true" ]]
}
minio_enabled() { [[ "$MESSAGE_FILESYSTEM_DISK" == "s3" || "$FILESYSTEM_DRIVER" == "s3" ]]; }
clamav_enabled() { [[ "$MESSAGE_ANTIVIRUS_ENABLED" == "true" ]]; }

# Start a service container once, reusing it across runs.
ensure_service() {
  local label="$1" name="$2"
  if ! exists_container "$name"; then
    log "Creating $label container"
    return 0
  fi
  if ! running_container "$name"; then
    log "Starting existing $label container"
    docker start "$name" >/dev/null
  else
    log "$label container is already running"
  fi
  return 1
}

# Services accept connections well after `docker run` returns, so probe until
# they answer instead of failing on the first attempt.
wait_for() {
  local label="$1" container="$2" timeout="$3"; shift 3
  local waited=0
  until "$@" >/dev/null 2>&1; do
    if (( waited >= timeout )); then
      die "$label health check failed after ${timeout}s. Check: docker logs $container"
    fi
    (( waited == 0 )) && log "Waiting for $label"
    sleep 3
    waited=$(( waited + 3 ))
  done
}

choose_image_workflow() {
  # Interactive operators choose explicitly. Automation can set
  # IMAGE_WORKFLOW_PROMPT=false and IMAGE_SOURCE=pull|build-push.
  if [[ "$IMAGE_WORKFLOW_PROMPT" == "true" && -t 0 ]]; then
    printf '\nApplication image workflow (%s):\n' "$IMAGE_NAME"
    printf '  1) Pull from Docker Hub, then provision (recommended)\n'
    printf '  2) Build locally, push to Docker Hub, then provision\n'
    local default_choice=1 choice
    [[ "$IMAGE_SOURCE" == "build-push" ]] && default_choice=2
    read -r -p "Choose 1 or 2 [$default_choice]: " choice
    choice="${choice:-$default_choice}"
    case "$choice" in
      1) IMAGE_SOURCE="pull" ;;
      2) IMAGE_SOURCE="build-push" ;;
      *) die "Invalid image workflow choice: $choice" ;;
    esac
  fi
  export IMAGE_SOURCE
  log "Image workflow selected: $IMAGE_SOURCE ($IMAGE_NAME)"
}

choose_image_workflow

choose_date_shift() {
  # Rewriting timestamps is a test-only convenience. A PROD environment keeps
  # its original dates no matter what SHIFT_DATES says.
  if [[ "$ENVIRONMENT_TYPE" != "TEST" ]]; then
    [[ "$SHIFT_DATES" == "yes" ]] && log "Ignoring SHIFT_DATES=yes because ENVIRONMENT_TYPE is $ENVIRONMENT_TYPE"
    SHIFT_DATES="no"
    return
  fi

  case "$SHIFT_DATES" in
    yes|no) return ;;
  esac

  if [[ ! -t 0 ]]; then
    SHIFT_DATES="no"
    log "No terminal attached; keeping the original dataset dates (set SHIFT_DATES=yes to shift)"
    return
  fi

  printf '\nTest dataset dates (%s):\n' "$ENVIRONMENT_TYPE"
  printf '  1) Keep the original dates as recorded in the dump\n'
  printf '  2) Shift every date to now, preserving the intervals between them\n'
  printf '     (makes recent allocations confirmable again instead of expired)\n'
  local choice
  read -r -p "Choose 1 or 2 [2]: " choice
  choice="${choice:-2}"
  case "$choice" in
    1) SHIFT_DATES="no" ;;
    2) SHIFT_DATES="yes" ;;
    *) die "Invalid date handling choice: $choice" ;;
  esac
}
choose_date_shift

require_env DB_PASSWORD
require_env DB_ROOT_PASSWORD
require_env ADMIN_EMAIL
require_env ADMIN_PASSWORD

app_key_is_valid() {
  local encoded decoded_length
  command -v openssl >/dev/null 2>&1 || return 1
  [[ "${APP_KEY:-}" == base64:* ]] || return 1
  encoded="${APP_KEY#base64:}"
  decoded_length="$(printf '%s' "$encoded" | openssl base64 -d -A 2>/dev/null | wc -c | tr -d ' ')"
  [[ "$decoded_length" == "32" ]]
}

persist_generated_app_key() {
  local temporary line replaced=0
  [[ -f "$PRIVATE_ENV_FILE" && -w "$PRIVATE_ENV_FILE" ]] || \
    die "APP_KEY is missing/invalid and $PRIVATE_ENV_FILE cannot be updated."
  umask 077
  temporary="${PRIVATE_ENV_FILE}.tmp.$$"
  : > "$temporary"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == APP_KEY=* ]]; then
      printf "APP_KEY='%s'\n" "$APP_KEY" >> "$temporary"
      replaced=1
    else
      printf '%s\n' "$line" >> "$temporary"
    fi
  done < "$PRIVATE_ENV_FILE"
  (( replaced == 1 )) || printf "APP_KEY='%s'\n" "$APP_KEY" >> "$temporary"
  mv -f "$temporary" "$PRIVATE_ENV_FILE"
  chmod 600 "$PRIVATE_ENV_FILE" 2>/dev/null || true
}

if ! app_key_is_valid; then
  command -v openssl >/dev/null 2>&1 || die "openssl is required to generate APP_KEY."
  APP_KEY="base64:$(openssl rand -base64 32 | tr -d '\r\n')"
  export APP_KEY
  persist_generated_app_key
  log "Generated and persisted a valid APP_KEY without printing it"
fi

if redis_enabled; then
  require_env REDIS_PASSWORD
  if [[ "$REDIS_HOST" == "127.0.0.1" || "$REDIS_HOST" == "localhost" ]]; then
    REDIS_HOST="$REDIS_CONTAINER"
    export REDIS_HOST
    log "Using Docker-network Redis host: $REDIS_HOST"
  fi
fi
if [[ "$MESSAGE_FILESYSTEM_DISK" == "s3" ]]; then
  require_env AWS_ACCESS_KEY_ID; require_env AWS_SECRET_ACCESS_KEY; require_env AWS_BUCKET; require_env AWS_ENDPOINT
  if [[ "$AWS_ENDPOINT" == "http://127.0.0.1:"* || "$AWS_ENDPOINT" == "http://localhost:"* ]]; then
    AWS_ENDPOINT="http://${MINIO_CONTAINER}:9000"
    export AWS_ENDPOINT
    log "Using Docker-network MinIO endpoint: $AWS_ENDPOINT"
  fi
fi
if [[ "$MESSAGE_ANTIVIRUS_ENABLED" == "true" && ( "$CLAMAV_HOST" == "127.0.0.1" || "$CLAMAV_HOST" == "localhost" ) ]]; then
  CLAMAV_HOST="$CLAMAV_CONTAINER"
  export CLAMAV_HOST
  log "Using Docker-network ClamAV host: $CLAMAV_HOST"
fi

# Forward differently named host variables to the official MySQL image without
# embedding their values in the docker command line.
export MYSQL_PASSWORD="$DB_PASSWORD"
export MYSQL_ROOT_PASSWORD="$DB_ROOT_PASSWORD"

command -v docker >/dev/null 2>&1 || die "Docker is not installed or is not on PATH."
docker info >/dev/null 2>&1 || die "Docker Desktop is not running."
[[ "$IMAGE_SOURCE" == "build" || "$IMAGE_SOURCE" == "build-push" || "$IMAGE_SOURCE" == "pull" ]] || die "IMAGE_SOURCE must be 'pull', 'build-push', or legacy 'build'."
if [[ "$IMAGE_SOURCE" == "build" || "$IMAGE_SOURCE" == "build-push" || "$ECHO_ENABLED" == "true" ]]; then
  [[ -d "$PROJECT_DIR" && -f "$PROJECT_DIR/Dockerfile" ]] || die "Invalid PROJECT_DIR: $PROJECT_DIR"
fi
[[ -d "$PRIVATE_DIR" ]] || die "Invalid PRIVATE_DIR: $PRIVATE_DIR"

# Git Bash/MSYS rewrites Linux-looking Docker arguments such as
# /private-import. Disable that conversion only for bind-mount docker calls and
# pass the source in native Windows form.
DOCKER_PRIVATE_DIR="$PRIVATE_DIR"
if [[ "${MSYSTEM:-}" == MINGW* ]] && command -v cygpath >/dev/null 2>&1; then
  DOCKER_PRIVATE_DIR="$(cygpath -w "$PRIVATE_DIR")"
fi

if [[ -z "$DUMP_FILE" ]]; then
  mapfile -t sql_files < <(find "$PRIVATE_DIR" -maxdepth 1 -type f -iname '*.sql' -print)
  if (( ${#sql_files[@]} == 1 )); then
    DUMP_FILE="$(basename -- "${sql_files[0]}")"
  elif (( ${#sql_files[@]} > 1 )); then
    die "Multiple SQL dumps found. Export DUMP_FILE with the filename to use."
  fi
fi

for private_filename in "$DUMP_FILE" "$SIRUTA_FILE" "$CLIENTS_FILE" "$PSIHOLOGI_FILE"; do
  [[ -z "$private_filename" || "$private_filename" =~ ^[A-Za-z0-9._-]+$ ]] || \
    die "Private filenames may contain only letters, digits, dot, underscore, and dash: $private_filename"
done

log "Ensuring private Docker network"
docker network inspect "$NETWORK_NAME" >/dev/null 2>&1 || docker network create "$NETWORK_NAME" >/dev/null

volume_created=0
if ! docker volume inspect "$DB_VOLUME" >/dev/null 2>&1; then
  log "Creating persistent database volume: $DB_VOLUME"
  docker volume create "$DB_VOLUME" >/dev/null
  volume_created=1
else
  log "Reusing persistent database volume: $DB_VOLUME"
fi

if ! exists_container "$DB_CONTAINER"; then
  log "Creating database container"
  docker run -d \
    --name "$DB_CONTAINER" \
    --restart unless-stopped \
    --network "$NETWORK_NAME" \
    -e MYSQL_DATABASE="$DB_NAME" \
    -e MYSQL_USER="$DB_USER" \
    -e MYSQL_PASSWORD \
    -e MYSQL_ROOT_PASSWORD \
    -v "$DB_VOLUME:/var/lib/mysql" \
    mysql:8.0 >/dev/null
elif ! running_container "$DB_CONTAINER"; then
  log "Starting existing database container"
  docker start "$DB_CONTAINER" >/dev/null
else
  log "Database container is already running"
fi

log "Waiting for MySQL readiness"
for attempt in {1..60}; do
  if docker exec "$DB_CONTAINER" sh -lc 'MYSQL_PWD="$MYSQL_PASSWORD" mysqladmin ping -h 127.0.0.1 -u "$MYSQL_USER" --silent' >/dev/null 2>&1; then
    break
  fi
  (( attempt == 60 )) && die "MySQL did not become ready. Check: docker logs $DB_CONTAINER"
  sleep 2
done

# Backing services start before the image is built or pulled so their warm-up
# overlaps that step. ClamAV in particular needs minutes on a cold volume.
if redis_enabled; then
  ensure_volume "$REDIS_VOLUME"
  if ensure_service Redis "$REDIS_CONTAINER"; then
    # The password is written to a config file inside the container so it never
    # appears in `docker inspect` args or in the redis-server process list.
    docker run -d \
      --name "$REDIS_CONTAINER" \
      --restart unless-stopped \
      --network "$NETWORK_NAME" \
      -e REDIS_PASSWORD \
      -v "$REDIS_VOLUME:/data" \
      "$REDIS_IMAGE" \
      sh -c 'set -e
        conf=/tmp/redis.conf
        umask 077
        printf "dir /data\nappendonly yes\n" > "$conf"
        if [ -n "${REDIS_PASSWORD:-}" ]; then
          printf "requirepass %s\n" "$REDIS_PASSWORD" >> "$conf"
        fi
        exec redis-server "$conf"' >/dev/null
  fi
fi

if minio_enabled; then
  require_env MINIO_ROOT_USER
  require_env MINIO_ROOT_PASSWORD
  require_env MINIO_BUCKET
  ensure_volume "$MINIO_VOLUME"
  if ensure_service MinIO "$MINIO_CONTAINER"; then
    docker run -d \
      --name "$MINIO_CONTAINER" \
      --restart unless-stopped \
      --network "$NETWORK_NAME" \
      -e MINIO_ROOT_USER \
      -e MINIO_ROOT_PASSWORD \
      -p "127.0.0.1:${MINIO_API_PORT}:9000" \
      -p "127.0.0.1:${MINIO_CONSOLE_PORT}:9001" \
      -v "$MINIO_VOLUME:/data" \
      "$MINIO_IMAGE" server /data --console-address ":9001" >/dev/null
  fi
fi

if clamav_enabled; then
  ensure_volume "$CLAMAV_VOLUME"
  if ensure_service ClamAV "$CLAMAV_CONTAINER"; then
    log "ClamAV downloads its virus database on first start; this can take minutes"
    docker run -d \
      --name "$CLAMAV_CONTAINER" \
      --restart unless-stopped \
      --network "$NETWORK_NAME" \
      ${CLAMAV_PLATFORM:+--platform "$CLAMAV_PLATFORM"} \
      -v "$CLAMAV_VOLUME:/var/lib/clamav" \
      "$CLAMAV_IMAGE" >/dev/null
  fi
fi

old_image_id="$(docker image inspect -f '{{.Id}}' "$IMAGE_NAME" 2>/dev/null || true)"
if [[ "$IMAGE_SOURCE" == "pull" ]]; then
  log "Pulling application image: $IMAGE_NAME ($DOCKER_PLATFORM)"
  docker pull --platform "$DOCKER_PLATFORM" "$IMAGE_NAME"
else
  log "Building application image (Docker cache is reused)"
  docker build --platform "$DOCKER_PLATFORM" --target runtime --build-arg MIX_ECHO_ENABLED="$MIX_ECHO_ENABLED" --build-arg MIX_ECHO_HOST="$MIX_ECHO_HOST" -t "$IMAGE_NAME" "$PROJECT_DIR"
  if [[ "$IMAGE_SOURCE" == "build-push" ]]; then
    log "Pushing application image to Docker Hub: $IMAGE_NAME"
    docker push "$IMAGE_NAME"
  fi
fi
new_image_id="$(docker image inspect -f '{{.Id}}' "$IMAGE_NAME")"
if [[ "$QUEUE_CONNECTION" == "redis" || "$CACHE_DRIVER" == "redis" || "$BROADCAST_DRIVER" == "redis" ]]; then
  docker run --rm --entrypoint php "$IMAGE_NAME" -r 'exit(extension_loaded("redis") && class_exists("Redis") ? 0 : 1);' || \
    die "The selected application image does not contain a working phpredis extension."
fi
image_changed=0
[[ "$old_image_id" == "$new_image_id" ]] || image_changed=1
config_hash="$(printf '%s\0' "$APP_URL" "$APP_KEY" "$APP_ENV" "$APP_DEBUG" "$DB_CONTAINER" "$DB_NAME" "$DB_USER" "$DB_PASSWORD" "$MAIL_MAILER" "$QUEUE_CONNECTION" "$BROADCAST_DRIVER" "$CACHE_DRIVER" "$FILESYSTEM_DRIVER" "$REDIS_HOST" "$REDIS_PORT" "$REDIS_PASSWORD" "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY" "$AWS_BUCKET" "$AWS_ENDPOINT" "$AWS_USE_PATH_STYLE_ENDPOINT" "$MESSAGE_FILESYSTEM_DISK" "$MESSAGE_ANTIVIRUS_ENABLED" "$CLAMAV_HOST" "$CLAMAV_PORT" "$CLAMAV_TIMEOUT" "$MIX_ECHO_ENABLED" "$MIX_ECHO_HOST" | sha256sum | awk '{print $1}')"

run_artisan() {
  MSYS_NO_PATHCONV=1 docker run --rm \
    --network "$NETWORK_NAME" \
    --mount "type=bind,source=$DOCKER_PRIVATE_DIR,target=/private-import,readonly" \
    -e DB_HOST="$DB_CONTAINER" \
    -e DB_PORT=3306 \
    -e DB_DATABASE="$DB_NAME" \
    -e DB_USERNAME="$DB_USER" \
    -e DB_PASSWORD \
    -e APP_KEY \
    "$IMAGE_NAME" php artisan "$@"
}

should_import=0
(( volume_created == 1 )) && should_import=1
[[ "$FORCE_IMPORT" == "1" ]] && should_import=1

# A raw dump brings its own schema and its own `migrations` table, so it has to
# land BEFORE migrate. Importing it afterwards would drop whatever the newer
# migrations just created and roll the recorded migration state back to
# whenever the dump was produced.
if (( should_import == 1 )) && [[ -n "$DUMP_FILE" && "$DUMP_IMPORT_MODE" == "raw" ]]; then
  [[ -f "$PRIVATE_DIR/$DUMP_FILE" ]] || die "Dump not found: $PRIVATE_DIR/$DUMP_FILE"
  [[ -f "$PRIVATE_DIR/$DUMP_IMPORTER" ]] || die "Importer not found: $PRIVATE_DIR/$DUMP_IMPORTER"
  log "Importing the self-contained SQL dump: $DUMP_FILE"
  MSYS_NO_PATHCONV=1 docker run --rm \
    --network "$NETWORK_NAME" \
    --mount "type=bind,source=$DOCKER_PRIVATE_DIR,target=/private-import,readonly" \
    "$IMAGE_NAME" php "/private-import/$DUMP_IMPORTER" \
      --host="$DB_CONTAINER" --db="$DB_NAME" --user="$DB_USER" --pass="$DB_PASSWORD" \
      --file="/private-import/$DUMP_FILE" --quiet \
    || die "Importing $DUMP_FILE failed."
fi

# Runs after a raw import so migrations newer than the dump are applied on top
# of it, which is what keeps an older dump usable against newer code.
log "Applying pending migrations (safe to repeat)"
set +e
migration_output="$(run_artisan migrate --force 2>&1)"
migration_status=$?
set -e
if (( migration_status != 0 )); then
  if [[ "$migration_output" == *"SQLSTATE[HY000] [1045]"* || "$migration_output" == *"Access denied for user"* ]]; then
    die "Database authentication failed. The persistent volume was initialized with different credentials. Set DB_PASSWORD in $PRIVATE_ENV_FILE to the password originally used for this volume, or use new DB_VOLUME/DB_CONTAINER/APP_CONTAINER names to initialize a separate environment. Existing MySQL volumes do not apply changed MYSQL_* passwords."
  fi
  printf '%s\n' "$migration_output" >&2
  die "Pending migrations failed. The application container was not replaced."
fi
printf '%s\n' "$migration_output"

if [[ -n "$DUMP_FILE" && "$DUMP_IMPORT_MODE" == "raw" ]]; then
  # A raw dump ships its own locality table and would overwrite anything
  # imported here, so the SIRUTA pass is pointless work in that mode.
  log "Raw dump selected; its own Romania locations will be used"
else
  locations_count="$(docker exec "$DB_CONTAINER" sh -lc 'MYSQL_PWD="$MYSQL_PASSWORD" mysql -N -s -h 127.0.0.1 -u "$MYSQL_USER" "$MYSQL_DATABASE" -e "SELECT COUNT(*) FROM romania_localities"' 2>/dev/null || printf '0')"
  if [[ ! "$locations_count" =~ ^[1-9][0-9]*$ ]]; then
    if [[ -f "$PRIVATE_DIR/$SIRUTA_FILE" ]]; then
      log "Romania locations are missing; importing $SIRUTA_FILE"
      run_artisan locations:import-romania --siruta="/private-import/$SIRUTA_FILE"
    else
      die "Romania locations are missing and $PRIVATE_DIR/$SIRUTA_FILE was not found."
    fi
  else
    log "Romania locations already exist; skipping location import"
  fi
fi

if (( should_import == 1 )); then
  if [[ -n "$DUMP_FILE" && "$DUMP_IMPORT_MODE" == "raw" ]]; then
    : # Already imported above, before the migrations ran.
  elif [[ -n "$DUMP_FILE" ]]; then
    [[ -f "$PRIVATE_DIR/$DUMP_FILE" ]] || die "Dump not found: $PRIVATE_DIR/$DUMP_FILE"
    log "Importing the selected SQL dump into the new volume"
    MSYS_NO_PATHCONV=1 docker run --rm \
      --network "$NETWORK_NAME" \
      --mount "type=bind,source=$DOCKER_PRIVATE_DIR,target=/private-import,readonly" \
      -e DB_HOST="$DB_CONTAINER" -e DB_PORT=3306 \
      -e DB_DATABASE="$DB_NAME" -e DB_USERNAME="$DB_USER" \
      -e DB_PASSWORD -e APP_KEY -e OLD_DB_PASSWORD="$DB_ROOT_PASSWORD" \
      "$IMAGE_NAME" sh -lc 'php artisan import:production-sql --sql="/private-import/'"$DUMP_FILE"'" --old-db=bluemonday_old_import --old-db-username=root --old-db-password="$OLD_DB_PASSWORD" --drop-old-db'
  elif [[ -f "$PRIVATE_DIR/$CLIENTS_FILE" || -f "$PRIVATE_DIR/$PSIHOLOGI_FILE" ]]; then
    csv_args=()
    [[ -f "$PRIVATE_DIR/$CLIENTS_FILE" ]] && csv_args+=(--clients="/private-import/$CLIENTS_FILE")
    [[ -f "$PRIVATE_DIR/$PSIHOLOGI_FILE" ]] && csv_args+=(--psihologi="/private-import/$PSIHOLOGI_FILE")
    log "No SQL dump selected; importing available production CSV files"
    run_artisan import:production-csv "${csv_args[@]}"
  else
    log "No production dump/CSV found; skipping private data import"
  fi
else
  log "Existing volume detected; skipping private data import (set FORCE_IMPORT=1 only when intentional)"
fi

# Runs whether or not the dump was re-imported, so an environment left running
# for a few days can be brought back to "now" without a full reprovision.
if [[ "$SHIFT_DATES" == "yes" ]]; then
  [[ -f "$PRIVATE_DIR/$SHIFT_DATES_SCRIPT" ]] || die "Date shifter not found: $PRIVATE_DIR/$SHIFT_DATES_SCRIPT"
  log "Shifting dataset dates to now (intervals between them are preserved)"
  MSYS_NO_PATHCONV=1 docker run --rm \
    --network "$NETWORK_NAME" \
    --mount "type=bind,source=$DOCKER_PRIVATE_DIR,target=/private-import,readonly" \
    "$IMAGE_NAME" php "/private-import/$SHIFT_DATES_SCRIPT" \
      --host="$DB_CONTAINER" --db="$DB_NAME" --user="$DB_USER" --pass="$DB_PASSWORD" \
    || die "Shifting the dataset dates failed."
fi

log "Creating or updating the admin account"
docker run --rm \
  --network "$NETWORK_NAME" \
  -e DB_HOST="$DB_CONTAINER" -e DB_PORT=3306 \
  -e DB_DATABASE="$DB_NAME" -e DB_USERNAME="$DB_USER" \
  -e DB_PASSWORD -e APP_KEY -e ADMIN_EMAIL -e ADMIN_PASSWORD \
  -e ADMIN_NAME="${ADMIN_NAME:-Private Admin}" \
  "$IMAGE_NAME" sh -lc 'php artisan users:create-admin --email="$ADMIN_EMAIL" --password="$ADMIN_PASSWORD" --name="$ADMIN_NAME"'

recreate_app=0
if ! exists_container "$APP_CONTAINER"; then
  recreate_app=1
elif [[ "$(docker inspect -f '{{.Image}}' "$APP_CONTAINER")" != "$new_image_id" ]]; then
  recreate_app=1
elif [[ "$(docker inspect -f '{{ index .Config.Labels \"bluemonday.private.config-hash\" }}' "$APP_CONTAINER" 2>/dev/null || true)" != "$config_hash" ]]; then
  recreate_app=1
fi

if (( recreate_app == 1 )); then
  if exists_container "$APP_CONTAINER"; then
    log "Replacing app container because a newer image is available"
    docker rm -f "$APP_CONTAINER" >/dev/null
  else
    log "Creating app container"
  fi
  docker run -d \
    --name "$APP_CONTAINER" \
    --restart unless-stopped \
    --label "bluemonday.private.config-hash=$config_hash" \
    --network "$NETWORK_NAME" \
    -p "$APP_PORT:80" \
    -e APP_URL="$APP_URL" -e APP_KEY -e APP_ENV -e APP_DEBUG \
    -e DB_HOST="$DB_CONTAINER" -e DB_PORT=3306 \
    -e DB_DATABASE="$DB_NAME" -e DB_USERNAME="$DB_USER" -e DB_PASSWORD \
    -e MAIL_MAILER -e MAIL_LOG_CHANNEL -e MAIL_FROM_ADDRESS -e MAIL_FROM_NAME \
    -e QUEUE_CONNECTION -e BROADCAST_DRIVER -e CACHE_DRIVER -e FILESYSTEM_DRIVER \
    -e REDIS_CLIENT -e REDIS_HOST -e REDIS_PORT -e REDIS_PASSWORD \
    -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION -e AWS_BUCKET -e AWS_ENDPOINT -e AWS_USE_PATH_STYLE_ENDPOINT \
    -e MESSAGE_PAGE_SIZE -e MESSAGE_MAX_ATTACHMENT_KB -e MESSAGE_FILESYSTEM_DISK -e MESSAGE_RETENTION_DAYS \
    -e MESSAGE_ANTIVIRUS_ENABLED -e MESSAGE_ALLOW_WITHOUT_ANTIVIRUS -e CLAMAV_HOST -e CLAMAV_PORT -e CLAMAV_TIMEOUT \
    -e MAIL_HOST -e MAIL_PORT -e MAIL_USERNAME -e MAIL_PASSWORD -e MAIL_ENCRYPTION \
    "$IMAGE_NAME" >/dev/null
elif ! running_container "$APP_CONTAINER"; then
  log "Starting existing app container"
  docker start "$APP_CONTAINER" >/dev/null
else
  log "App image is unchanged and the container is already running"
fi

runtime_env=(
  -e APP_URL -e APP_KEY -e APP_ENV -e APP_DEBUG
  -e DB_HOST="$DB_CONTAINER" -e DB_PORT=3306 -e DB_DATABASE="$DB_NAME" -e DB_USERNAME="$DB_USER" -e DB_PASSWORD
  -e QUEUE_CONNECTION -e BROADCAST_DRIVER -e CACHE_DRIVER -e FILESYSTEM_DRIVER
  -e REDIS_CLIENT -e REDIS_HOST -e REDIS_PORT -e REDIS_PASSWORD
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION -e AWS_BUCKET -e AWS_ENDPOINT -e AWS_USE_PATH_STYLE_ENDPOINT
  -e MESSAGE_PAGE_SIZE -e MESSAGE_MAX_ATTACHMENT_KB -e MESSAGE_FILESYSTEM_DISK -e MESSAGE_RETENTION_DAYS
  -e MESSAGE_ANTIVIRUS_ENABLED -e MESSAGE_ALLOW_WITHOUT_ANTIVIRUS -e CLAMAV_HOST -e CLAMAV_PORT -e CLAMAV_TIMEOUT
)

log "Checking application infrastructure"
docker exec "$APP_CONTAINER" php -r 'exit(extension_loaded("redis") ? 0 : 1);' || die "The application image does not contain phpredis. Rebuild the image without cache."
if redis_enabled; then
  wait_for Redis "$REDIS_CONTAINER" "$SERVICE_HEALTH_TIMEOUT" \
    docker exec -e REDIS_HOST -e REDIS_PORT -e REDIS_PASSWORD "$APP_CONTAINER" php -r '$r=new Redis(); $r->connect(getenv("REDIS_HOST"),(int)getenv("REDIS_PORT"),3); if(getenv("REDIS_PASSWORD")!==""){$r->auth(getenv("REDIS_PASSWORD"));} exit($r->ping()?0:1);'
fi
if minio_enabled; then
  wait_for MinIO "$MINIO_CONTAINER" "$SERVICE_HEALTH_TIMEOUT" \
    docker exec -e AWS_ENDPOINT "$APP_CONTAINER" sh -lc 'curl -fsS "$AWS_ENDPOINT/minio/health/live" >/dev/null'

  log "Ensuring private MinIO bucket: $MINIO_BUCKET"
  docker run --rm \
    --network "$NETWORK_NAME" \
    -e MINIO_ROOT_USER \
    -e MINIO_ROOT_PASSWORD \
    -e MINIO_BUCKET \
    -e MINIO_ENDPOINT="http://${MINIO_CONTAINER}:9000" \
    --entrypoint sh \
    "$MINIO_MC_IMAGE" -c 'set -e
      mc alias set private "$MINIO_ENDPOINT" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
      mc mb --ignore-existing "private/$MINIO_BUCKET" >/dev/null
      mc anonymous set none "private/$MINIO_BUCKET" >/dev/null' >/dev/null \
    || die "Could not create or verify the private MinIO bucket: $MINIO_BUCKET"
fi
if clamav_enabled; then
  wait_for ClamAV "$CLAMAV_CONTAINER" "$CLAMAV_HEALTH_TIMEOUT" \
    docker exec -e CLAMAV_HOST -e CLAMAV_PORT "$APP_CONTAINER" php -r '$s=@fsockopen(getenv("CLAMAV_HOST"),(int)getenv("CLAMAV_PORT"),$n,$m,3); exit(is_resource($s)?0:1);'
fi

if [[ "$QUEUE_CONNECTION" != "sync" ]]; then
  log "Creating/replacing queue worker"
  exists_container "$WORKER_CONTAINER" && docker rm -f "$WORKER_CONTAINER" >/dev/null
  docker run -d --name "$WORKER_CONTAINER" --restart unless-stopped --no-healthcheck --network "$NETWORK_NAME" \
    "${runtime_env[@]}" \
    "$IMAGE_NAME" php artisan queue:work "$QUEUE_CONNECTION" --queue=attachments,notifications,default \
      --sleep=1 --tries=3 --backoff=5 --timeout=180 --max-time=3600 >/dev/null
fi

log "Creating/replacing scheduler"
exists_container "$SCHEDULER_CONTAINER" && docker rm -f "$SCHEDULER_CONTAINER" >/dev/null
docker run -d --name "$SCHEDULER_CONTAINER" --restart unless-stopped --no-healthcheck --network "$NETWORK_NAME" \
  "${runtime_env[@]}" \
  "$IMAGE_NAME" sh -lc 'while true; do php artisan schedule:run --no-interaction; sleep 60; done' >/dev/null

if [[ "$ECHO_ENABLED" == "true" ]]; then
  [[ "$BROADCAST_DRIVER" == "redis" ]] || die "ECHO_ENABLED=true requires BROADCAST_DRIVER=redis."
  log "Building and creating/replacing Laravel Echo Server"
  docker build -t "$ECHO_IMAGE" "$PROJECT_DIR/docker/echo"
  exists_container "$ECHO_CONTAINER" && docker rm -f "$ECHO_CONTAINER" >/dev/null
  docker run -d --name "$ECHO_CONTAINER" --restart unless-stopped --network "$NETWORK_NAME" \
    -p "127.0.0.1:${ECHO_PORT}:6001" \
    -e REDIS_HOST -e REDIS_PORT -e REDIS_PASSWORD -e ECHO_PORT=6001 \
    -e ECHO_AUTH_HOST="http://${APP_CONTAINER}" \
    "$ECHO_IMAGE" >/dev/null
fi

log "Ready: $APP_URL"
printf 'Volume: %s\nDatabase container: %s\nApplication container: %s\n' "$DB_VOLUME" "$DB_CONTAINER" "$APP_CONTAINER"
