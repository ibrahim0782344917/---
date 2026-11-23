#!/data/data/com.termux/files/usr/bin/bash
# Diagnostic only: restore four APPLICATION tables from the encrypted backup into
# a disposable, private, local PostgreSQL database. NOT a full Supabase restore.
set -euo pipefail
umask 077
if [[ -z "$PREFIX" ]]; then echo "Use Termux" >&2; exit 1; fi
ARCH="$HOME/alani-supabase-20261122-190549.dump.enc"
[[ -s "$ARCH" ]] || { echo "BACKUP_NOT_FOUND" >&2; exit 1; }
for cmd in pg_isready psql pg_restore createdb dropdb openssl; do
  command -v "$cmd" >/dev/null || { echo "MISSING_TOOL:$cmd" >&2; exit 1; }
done
SOCKET="$PREFIX/tmp"
PORT=55432
if ! pg_isready -q -h "$SOCKET" -p "$PORT" -U postgres; then
  echo "Local PostgreSQL not running. Start the existing lab:"
  echo "pg_ctl -D \"\$HOME/alani-restore-lab\" -l \"\$HOME/alani-restore-lab.log\" -o \"-p 55432 -c listen_addresses='' -k \$PREFIX/tmp\" start"
  exit 1
fi
local_psql() { psql -X -qAt -v ON_ERROR_STOP=1 -h "$SOCKET" -p "$PORT" -U postgres "$@"; }
[[ -z "$(local_psql -d postgres -c 'show listen_addresses;')" ]] || {
  echo "STOP: this local test server must not expose a TCP listener." >&2; exit 1;
}
DB="alani_core_probe_$(date -u +%s)_$RANDOM"
createdb -h "$SOCKET" -p "$PORT" -U postgres "$DB"
cleanup(){
  unset PASSPHRASE 2>/dev/null || true
  dropdb -h "$SOCKET" -p "$PORT" -U postgres "$DB" >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Plain TEXT columns suffice to verify COPY data can be restored, avoiding
# Supabase-only extensions, triggers and special database roles.
local_psql -d "$DB" <<'SQL'
create table public.orders (
 id text, buyer_id text, store_id text, status text, payment_method text,
 delivery_address text, phone text, notes text, total_iqd text,
 created_at text, updated_at text
);
create table public.order_items (
 id text, order_id text, product_id text, product_name text,
 unit_price_iqd text, quantity text, line_total_iqd text
);
create table public.products (
 id text, store_id text, name text, description text, price_iqd text,
 image_url text, is_active text, created_at text, stock_quantity text
);
create table public.alani_publications (
 id text, store_id text, kind text, title text, body text,
 ingredients text, safety_note text, image_url text, video_url text,
 status text, published_at text, created_at text, updated_at text,
 created_by text
);
SQL
read -r -s -p 'Backup ENCRYPTION passphrase (hidden): ' PASSPHRASE
printf '\n'
[[ -n "$PASSPHRASE" ]] || { echo "EMPTY_PASSPHRASE" >&2; exit 1; }
echo "Restoring ONLY app records into disposable LOCAL PostgreSQL..."
openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 \
  -pass fd:3 -in "$ARCH" 3<<<"$PASSPHRASE" |
  pg_restore --data-only --no-owner --no-privileges \
    --table=orders --table=order_items \
    --table=products --table=alani_publications --file=- |
  psql -X -v ON_ERROR_STOP=1 --single-transaction \
    -h "$SOCKET" -p "$PORT" -U postgres -d "$DB" >/dev/null
unset PASSPHRASE
echo 'Non-sensitive restore counts (snapshot from 22 Nov 2026):'
local_psql -d "$DB" <<'SQL'
select 'orders',count(*) from public.orders
 where store_id='25091ca2-c0da-416c-b634-81b188ee66be';
select 'order_items',count(*) from public.order_items;
select 'products',count(*) from public.products
 where store_id='25091ca2-c0da-416c-b634-81b188ee66be';
select 'publications',count(*) from public.alani_publications
 where store_id='25091ca2-c0da-416c-b634-81b188ee66be';
select 'historic_total_iqd',coalesce(sum(total_iqd::bigint),0)
 from public.orders
 where store_id='25091ca2-c0da-416c-b634-81b188ee66be';
SQL
pass=$(local_psql -d "$DB" -c "
select count(*)=5
 and (select count(*) from public.order_items)=5
 and (select count(*) from public.products
      where store_id='25091ca2-c0da-416c-b634-81b188ee66be')=3
 and (select count(*) from public.alani_publications
      where store_id='25091ca2-c0da-416c-b634-81b188ee66be')=4
 and coalesce(sum(total_iqd::bigint),0)=120000
 from public.orders where store_id='25091ca2-c0da-416c-b634-81b188ee66be';")
if [[ "$pass" == "t" ]]; then
  echo "CORE_DATA_RESTORE_PASS: four critical tables restored and validated."
  echo "NOT_A_FULL_SUPABASE_RESTORE: extension/auth/platform objects remain untested."
else
  echo "CORE_DATA_RESTORE_MISMATCH: do not enable checkout." >&2
  exit 1
fi
echo "Deleting temporary local test database; encrypted backup remains intact."
