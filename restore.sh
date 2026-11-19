#!/usr/bin/env bash
# Restore file .bak dari folder ./backup ke container SQL Server.
#
#   ./restore.sh <file.bak> [nama_database] [nomor_backup_set]
#
# Nama database default diambil dari nama file. Database yang sudah ada tidak
# akan ditimpa: skrip berhenti dengan pesan error.
set -euo pipefail
cd "$(dirname "$0")"

die() { echo "Error: $*" >&2; exit 1; }

[[ $# -ge 1 ]] || die "pemakaian: ./restore.sh <file.bak> [nama_database] [nomor_backup_set]"

file="$(basename "$1")"
db="${2:-${file%.*}}"
set_no="${3:-}"

[[ -f "backup/$file" ]] || die "backup/$file tidak ditemukan. Salin dulu file .bak ke folder ./backup"
[[ -z "$set_no" || "$set_no" =~ ^[0-9]+$ ]] || die "nomor backup set harus berupa angka"

# Password dibaca di dalam container agar tidak muncul di daftar proses host.
sql() {
  docker compose exec -T mssql sh -c \
    'SQLCMDPASSWORD="$MSSQL_SA_PASSWORD" exec /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -b -r1 -x -I "$@"' \
    sh "$@"
}

docker compose exec -T mssql test -r "/backup/$file" \
  || die "container tidak bisa membaca backup/$file. Coba: chmod 644 'backup/$file'"

bak_literal="/backup/${file//\'/\'\'}"
db_literal="${db//\'/\'\'}"
db_ident="${db//]/]]}"
db_safe="${db//[^A-Za-z0-9_-]/_}"

# RESTORE sendiri tidak selalu menolak: database yang berasal dari backup yang
# sama bisa tertimpa tanpa peringatan, jadi dicek di sini.
exists="$(sql -h -1 -W -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.databases WHERE name = N'$db_literal'")"
[[ "$exists" == "0" ]] || die "database [$db] sudah ada. Pakai nama lain, atau hapus dulu dengan DROP DATABASE"

# Satu file .bak bisa berisi beberapa backup. Tanpa FILE = n, SQL Server memakai
# yang pertama (biasanya paling lama), jadi harus dipilih secara eksplisit.
header="$(sql -h -1 -W -s $'\t' -Q "SET NOCOUNT ON; RESTORE HEADERONLY FROM DISK = N'$bak_literal'")"
sets="$(grep -c . <<<"$header")"

if [[ -z "$set_no" ]]; then
  if [[ "$sets" -gt 1 ]]; then
    echo "File ini berisi $sets backup. Pilih satu sebagai argumen ketiga:" >&2
    echo "(tipe: 1 = full, 2 = log, 5 = differential)" >&2
    awk -F'\t' '{ printf "  nomor %s  tipe %s  db %s  tanggal %s\n", $6, $3, $10, $18 }' <<<"$header" >&2
    exit 1
  fi
  set_no=1
fi

selected="$(awk -F'\t' -v n="$set_no" '$6 == n' <<<"$header")"
[[ -n "$selected" ]] || die "backup set nomor $set_no tidak ada di file ini"
awk -F'\t' '{ printf "Sumber: db %s, server %s, SQL Server versi mayor %s, compatibility level %s\n", $10, $9, $26, $24 }' <<<"$selected"

filelist="$(sql -h -1 -W -s $'\t' -Q "SET NOCOUNT ON; RESTORE FILELISTONLY FROM DISK = N'$bak_literal' WITH FILE = $set_no")"

# Path di dalam backup masih path Windows (C:\...), jadi setiap file perlu MOVE.
moves=""
first_data=1
while IFS=$'\t' read -r logical physical type _; do
  [[ -n "$logical" ]] || continue
  case "$type" in
    D) if [[ $first_data -eq 1 ]]; then ext=".mdf"; first_data=0; else ext=".ndf"; fi ;;
    L) ext=".ldf" ;;
    *) ext="" ;; # S = FILESTREAM / in-memory, F = full-text: berupa folder
  esac
  target="/var/opt/mssql/data/${db_safe}_${logical//[^A-Za-z0-9_-]/_}${ext}"
  moves+=", MOVE N'${logical//\'/\'\'}' TO N'$target'"
  echo "  $physical -> $target"
done <<<"$filelist"

[[ -n "$moves" ]] || die "daftar file di dalam backup kosong"

echo "Restore ke database [$db]..."
sql -Q "RESTORE DATABASE [$db_ident] FROM DISK = N'$bak_literal' WITH FILE = $set_no$moves, STATS = 10"

sql -W -Q "SET NOCOUNT ON; SELECT name, state_desc, compatibility_level FROM sys.databases WHERE name = N'$db_literal'"
