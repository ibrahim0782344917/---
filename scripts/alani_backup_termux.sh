#!/data/data/com.termux/files/usr/bin/bash
# Al-Ani encrypted logical backup from an Android phone running Termux.
# No backup data or credentials are uploaded to GitHub or ChatGPT.
set -euo pipefail
REF='ltwncrewggdrjevakwpb'
for prog in pg_dump pg_restore openssl sha256sum; do
  if ! command -v "$prog" >/dev/null 2>&1; then
    printf 'Missing %s. Install: pkg install postgresql openssl\n' "$prog" >&2
    exit 1
  fi
done

printf '\nAl-Ani encrypted database backup - read-only.\n'
printf 'Source project: %s\n' "$REF"
printf 'In the Supabase Dashboard open Connect > Session pooler.\n'
read -r -p 'Host (not the entire database URL): ' DB_HOST
case "$DB_HOST" in
  *.pooler.supabase.com|db.*.supabase.co) ;;
  *) printf 'Host must be the Supabase Connect host.\n' >&2; exit 1 ;;
esac
read -r -p 'Database username: ' DB_USER
if [[ "$DB_USER" != "postgres.$REF" && "$DB_USER" != "postgres" ]]; then
  printf 'This script is restricted to the intended project.\n' >&2
  exit 1
fi
read -r -s -p 'Database password (never sent to chat): ' DB_PASS
printf '\n'
if [[ -z "$DB_PASS" ]]; then printf 'Password required.\n' >&2; exit 1; fi
read -r -s -p 'New backup encryption passphrase: ' BACKUP_PASS
printf '\n'
read -r -s -p 'Repeat encryption passphrase: ' BACKUP_CONFIRM
printf '\n'
if [[ -z "$BACKUP_PASS" || "$BACKUP_PASS" != "$BACKUP_CONFIRM" ]]; then
  printf 'Encryption passphrases did not match.\n' >&2
  exit 1
fi
unset BACKUP_CONFIRM
export PGHOST="$DB_HOST" PGPORT=5432 PGUSER="$DB_USER" PGDATABASE=postgres
export PGSSLMODE=require PGPASSWORD="$DB_PASS"
unset DB_PASS DB_HOST DB_USER
umask 077
DEST="$HOME/alani-supabase-$(date -u +%Y%m%d-%H%M%S).dump.enc"
PARTIAL="$DEST.partial"
trap 'rm -f "$PARTIAL"; unset PGPASSWORD BACKUP_PASS' EXIT
if [[ -e "$DEST" ]]; then printf 'Backup destination exists.\n' >&2; exit 1; fi

printf 'Dumping database read-only and encrypting directly to file...\n'
pg_dump --format=custom --no-owner --no-privileges --no-password --dbname=postgres |
  openssl enc -aes-256-cbc -salt -pbkdf2 -iter 600000 -pass fd:3 -out "$PARTIAL" 3<<<"$BACKUP_PASS"
unset PGPASSWORD
if [[ ! -s "$PARTIAL" ]]; then
  printf 'Empty backup; operation failed.\n' >&2; exit 1
fi
mv "$PARTIAL" "$DEST"
chmod 600 "$DEST"

printf 'Checking archive catalog locally (this is NOT a restore test)...\n'
openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -pass fd:3 -in "$DEST" 3<<<"$BACKUP_PASS" |
  pg_restore --list >/dev/null
unset BACKUP_PASS
printf '\nEncrypted archive: %s\n' "$DEST"
sha256sum "$DEST"
printf 'Store this encrypted file in private off-device storage.\n'
printf 'Before enabling sales, RESTORE TEST in a separate database is mandatory.\n'
printf 'Note: database dumps do NOT include actual Supabase Storage media files,\n'
printf 'platform-level settings, or role passwords; back those up separately.\n'
