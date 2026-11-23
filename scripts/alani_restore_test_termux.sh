#!/data/data/com.termux/files/usr/bin/bash
# Local-only encrypted backup restore check for Android Termux.
set -euo pipefail
umask 077
[[ -n "$PREFIX" ]] || { echo "Run inside Termux." >&2; exit 1; }
ARCH="$HOME/alani-supabase-20261122-190549.dump.enc"
COPY="$HOME/storage/downloads/alani-supabase-20261122-190549.dump.enc"
LAB="$HOME/alani-restore-lab"
SOCKET="$PREFIX/tmp"
PORT=55432
DB=alani_restore_test
for binary in initdb pg_ctl pg_isready psql pg_restore createdb openssl sha256sum; do
  command -v "$binary" >/dev/null || { echo "MISSING_TOOL:$binary" >&2; exit 1; }
done
for file in "$ARCH" "$COPY"; do
  [[ -s "$file" ]] || { printf 'MISSING_BACKUP:%s\n' "$file" >&2; exit 1; }
done
sourcehash=$(sha256sum "$ARCH" | cut -d' ' -f1)
copyhash=$(sha256sum "$COPY" | cut -d' ' -f1)
[[ "$sourcehash" == "$copyhash" ]] || { echo "BACKUP_COPIES_DIFFER" >&2; exit 1; }
echo "PASS: encrypted backup and copy have matching checksums."
if [[ ! -d "$LAB" ]]; then
  initdb -D "$LAB" -U postgres --encoding=UTF8 --no-locale \
    --auth-local=trust --auth-host=reject >/dev/null
fi
if ! pg_isready -q -h "$SOCKET" -p "$PORT" -U postgres; then
  pg_ctl -D "$LAB" -l "$HOME/alani-restore-lab.log" \
     -o "-p $PORT -c listen_addresses='' -k $SOCKET" start >/dev/null
fi
ready=false
for i in 1 2 3 4 5 6 7 8 9 10; do
  if pg_isready -q -h "$SOCKET" -p "$PORT" -U postgres; then
    ready=true; break
  fi
  sleep 1
done
[[ "$ready" == true ]] || { echo "LOCAL_DB_NOT_READY" >&2; exit 1; }
psql_local() { psql -X -qAt -v ON_ERROR_STOP=1 -h "$SOCKET" -p "$PORT" -U postgres "$@"; }
listen=$(psql_local -d postgres -c 'show listen_addresses;')
[[ -z "$listen" ]] || { echo "LOCAL_SERVER_NETWORK_EXPOSED" >&2; exit 1; }
if psql_local -d postgres -c "select 1 from pg_database where datname='$DB'" | grep -qx 1; then
  existing=$(psql_local -d "$DB" -c \
    "select count(*) from pg_tables where schemaname not in ('pg_catalog','information_schema')")
  [[ "$existing" == "0" ]] || {
    echo "STOP: local test DB contains tables; will not overwrite." >&2
    exit 1
  }
else
  createdb -h "$SOCKET" -p "$PORT" -U postgres "$DB"
fi
read -r -s -p 'Backup encryption passphrase (hidden): ' PHRASE
printf '\n'
[[ -n "$PHRASE" ]] || { echo "EMPTY_PASSPHRASE" >&2; exit 1; }
trap 'unset PHRASE' EXIT
echo "Checking decrypted backup catalog..."
openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -pass fd:3 \
  -in "$ARCH" 3<<<"$PHRASE" | pg_restore --list >/dev/null
echo "Restoring into private local DB only. Production is never contacted."
openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -pass fd:3 \
  -in "$ARCH" 3<<<"$PHRASE" |
    pg_restore --host="$SOCKET" --port="$PORT" --username=postgres \
      --dbname="$DB" --no-owner --no-privileges \
      --single-transaction --exit-on-error
unset PHRASE
echo "Checking expected historic order and product counts..."
count_orders=$(psql_local -d "$DB" -c \
  "select count(*) from public.orders where store_id='25091ca2-c0da-416c-b634-81b188ee66be'")
count_products=$(psql_local -d "$DB" -c \
  "select count(*) from public.products where store_id='25091ca2-c0da-416c-b634-81b188ee66be'")
count_posts=$(psql_local -d "$DB" -c \
  "select count(*) from public.alani_publications where store_id='25091ca2-c0da-416c-b634-81b188ee66be'")
printf 'RESTORE_COUNTS: orders=%s products=%s publications=%s\n' \
  "$count_orders" "$count_products" "$count_posts"
[[ "$count_orders" -ge 5 && "$count_products" -ge 3 && "$count_posts" -ge 4 ]] || {
  echo "RESTORE_COUNTS_UNEXPECTED: Checkout must remain disabled." >&2; exit 1;
}
echo "RESTORE_TEST_PASS: historic application records can be read locally."
echo "Supabase Storage media files are not included in pg_dump."
