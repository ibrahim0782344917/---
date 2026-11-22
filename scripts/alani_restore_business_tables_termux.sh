#!/data/data/com.termux/files/usr/bin/bash
# Al-Ani PARTIAL DATA restore test: local table schemas + rows only.
# This cannot prove a full Supabase restore; do NOT use this DB for live sales.
set -euo pipefail
umask 077
ARCH="$HOME/alani-supabase-20261122-190549.dump.enc"
COPY="$HOME/storage/downloads/alani-supabase-20261122-190549.dump.enc"
SOCKET="$PREFIX/tmp"
PORT=55432
DB=alani_verify_business
for prog in psql pg_restore createdb pg_isready openssl sha256sum; do
  command -v "$prog" >/dev/null || { echo "MISSING:$prog" >&2; exit 1; }
done
[[ -s "$ARCH" && -s "$COPY" ]] || {
  echo 'Encrypted original and Downloads copy are both required.' >&2; exit 1;
}
ORIGINAL_HASH=$(sha256sum "$ARCH" | cut -d' ' -f1)
COPY_HASH=$(sha256sum "$COPY" | cut -d' ' -f1)
[[ "$ORIGINAL_HASH" == "$COPY_HASH" ]] || {
  echo 'STOP: encrypted backup copies differ.' >&2; exit 1;
}
echo 'PASS: encrypted backup copies match SHA-256.'
pg_isready -q -h "$SOCKET" -p "$PORT" -U postgres || {
  echo 'Local PostgreSQL not running on Termux socket port 55432.' >&2; exit 1;
}
psql_local() { psql -X -qAt -v ON_ERROR_STOP=1 \
  -h "$SOCKET" -p "$PORT" -U postgres "$@"; }
[[ -z "$(psql_local -d postgres -c 'show listen_addresses;')" ]] || {
  echo 'STOP: local DB has TCP listening enabled.' >&2; exit 1;
}
if psql_local -d postgres -c \
  "select 1 from pg_database where datname='$DB'" | grep -qx 1; then
  echo "STOP: local test DB already exists; nothing overwritten." >&2; exit 1;
fi
createdb -h "$SOCKET" -p "$PORT" -U postgres "$DB"
read -r -s -p 'Backup encryption passphrase (hidden): ' PHRASE
printf '\n'
[[ -n "$PHRASE" ]] || { echo 'EMPTY_PASSPHRASE' >&2; exit 1; }
trap 'unset PHRASE' EXIT
echo 'Step 1/2: restoring standard business table structures locally.'
openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -pass fd:3 \
  -in "$ARCH" 3<<<"$PHRASE" |
  pg_restore --host="$SOCKET" --port="$PORT" --username=postgres \
    --dbname="$DB" --no-owner --no-privileges \
    --schema-only --section=pre-data --single-transaction --exit-on-error \
    --table=orders --table=order_items --table=products --table=alani_publications
echo 'Step 2/2: restoring selected table rows locally.'
openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -pass fd:3 \
  -in "$ARCH" 3<<<"$PHRASE" |
  pg_restore --host="$SOCKET" --port="$PORT" --username=postgres \
    --dbname="$DB" --no-owner --no-privileges \
    --data-only --single-transaction --exit-on-error \
    --table=orders --table=order_items --table=products --table=alani_publications
unset PHRASE
COUNTS=$(psql_local -d "$DB" -F ' ' -c \
  'select (select count(*) from public.orders),
          (select count(*) from public.order_items),
          (select count(*) from public.products),
          (select count(*) from public.alani_publications),
          (select coalesce(sum(total_iqd),0) from public.orders);')
read -r ORDERS LINES PRODUCTS POSTS AMOUNT <<<"$COUNTS"
printf 'LOCAL_BUSINESS_RESTORE: orders=%s lines=%s products=%s posts=%s total_iqd=%s\n' \
  "$ORDERS" "$LINES" "$PRODUCTS" "$POSTS" "$AMOUNT"
[[ "$ORDERS" == 5 && "$LINES" == 5 && "$PRODUCTS" == 3 &&
   "$POSTS" == 4 && "$AMOUNT" == 120000 ]] || {
  echo 'CHECK_FAILED: restored counts do not match expected old records.' >&2; exit 1;
}
echo 'BUSINESS_TABLES_RESTORE_PASS: key tables recovered locally.'
echo 'NOT FULL SUPABASE RESTORE: auth, vault, storage and RLS untested.'
