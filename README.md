# SQL Server 2022 di Docker

Setup Docker Compose untuk menjalankan SQL Server 2022 di Linux, lengkap dengan CloudBeaver (klien database berbasis web, pengganti SSMS) dan skrip untuk me-restore file `.bak`.

Cocok untuk membuka backup dari SQL Server versi lama (misalnya 2016) di mesin Linux: backup dari versi lama bisa langsung di-restore ke 2022.

## Isi

| Service | Image | Alamat |
| --- | --- | --- |
| `mssql` | `mcr.microsoft.com/mssql/server:2022-latest` | `localhost:1433` |
| `cloudbeaver` | `dbeaver/cloudbeaver:26.2.4` | http://localhost:8978 |

Kedua port hanya dibuka ke `127.0.0.1`, jadi tidak bisa diakses dari komputer lain di jaringan.

## Prasyarat

- Docker dengan plugin Compose (`docker compose`)
- RAM kosong sekitar 5 GB dengan pengaturan default (4 GB untuk SQL Server, 1 GB untuk CloudBeaver)

## Cara pakai

### 1. Siapkan file `.env`

```bash
cp .env.example .env
```

Lalu isi `MSSQL_SA_PASSWORD` dan `CLOUDBEAVER_ADMIN_PASSWORD`. Keduanya wajib; Compose akan menolak jalan kalau kosong.

Password SA harus memenuhi aturan SQL Server: minimal 8 karakter dan mengandung tiga dari empat jenis karakter (huruf besar, huruf kecil, angka, simbol). Kalau tidak, container `mssql` akan langsung berhenti.

### 2. Jalankan

```bash
docker compose up -d
docker compose ps
```

CloudBeaver baru menyala setelah SQL Server berstatus `healthy`, biasanya kurang dari satu menit.

### 3. Restore backup

Salin file `.bak` ke folder `backup/`, lalu:

```bash
./restore.sh <file.bak> [nama_database] [nomor_backup_set]
```

Contoh:

```bash
./restore.sh TOPS.bak              # database bernama TOPS
./restore.sh TOPS.bak TUNAS1       # database bernama TUNAS1
./restore.sh TOPS.bak TUNAS1 2     # pakai backup set nomor 2
```

Yang dilakukan skrip ini:

- Nama database default diambil dari nama file.
- Database yang sudah ada tidak ditimpa; skrip berhenti dengan pesan error.
- Kalau satu file berisi beberapa backup, skrip menampilkan daftarnya dan meminta nomor backup set sebagai argumen ketiga.
- Path file Windows di dalam backup (`C:\...`) otomatis dipindahkan ke `/var/opt/mssql/data/`.

Kalau muncul error bahwa container tidak bisa membaca file, jalankan `chmod 644 backup/<file.bak>`.

### 4. Buka database

**Lewat CloudBeaver:** buka http://localhost:8978 dan login dengan `CLOUDBEAVER_ADMIN_NAME` / `CLOUDBEAVER_ADMIN_PASSWORD`. Koneksi bernama `TUNAS1` sudah tersedia; saat membukanya, masukkan user `sa` dan password SA.

Koneksi itu mengarah ke database bernama `TUNAS1`. Kalau nama database Anda berbeda, ubah `cloudbeaver/initial-data-sources.conf` sebelum pertama kali menjalankan `docker compose up`, atau buat koneksi baru dari dalam CloudBeaver. File ini hanya dibaca saat volume CloudBeaver pertama kali dibuat.

**Lewat klien lain** (DBeaver, Azure Data Studio, aplikasi Anda):

| | |
| --- | --- |
| Host | `localhost` |
| Port | `1433` |
| User | `sa` |
| Password | isi `MSSQL_SA_PASSWORD` |
| Opsi | `TrustServerCertificate=true` |

**Lewat `sqlcmd` di dalam container:**

```bash
docker compose exec mssql sh -c \
  'SQLCMDPASSWORD="$MSSQL_SA_PASSWORD" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C'
```

## Konfigurasi

Semua diatur lewat `.env`:

| Variabel | Default | Keterangan |
| --- | --- | --- |
| `MSSQL_SA_PASSWORD` | wajib diisi | Password user `sa` |
| `MSSQL_PORT` | `1433` | Port SQL Server di host |
| `MSSQL_MEMORY_LIMIT_MB` | `4096` | Batas memori SQL Server |
| `MSSQL_PID` | `Developer` | Edisi SQL Server |
| `CLOUDBEAVER_ADMIN_NAME` | `cbadmin` | User admin CloudBeaver |
| `CLOUDBEAVER_ADMIN_PASSWORD` | wajib diisi | Password admin CloudBeaver |
| `CLOUDBEAVER_PORT` | `8978` | Port CloudBeaver di host |

Untuk membuka akses dari jaringan, hapus `127.0.0.1:` pada bagian `ports` di `docker-compose.yml`.

## Menghentikan dan menghapus

```bash
docker compose down       # berhenti, data tetap ada
docker compose down -v    # berhenti dan HAPUS semua database serta pengaturan CloudBeaver
```

Data disimpan di volume Docker `mssql_data` dan `cloudbeaver_data`, bukan di folder ini.

## Catatan

- Edisi Developer gratis tetapi lisensinya hanya untuk pengembangan dan pengujian, bukan produksi.
- Dengan menjalankan container ini Anda menyetujui EULA SQL Server (`ACCEPT_EULA=Y`).
- File `.env` dan isi folder `backup/` tidak ikut masuk ke Git.
- Mengubah `MSSQL_SA_PASSWORD` di `.env` setelah volume dibuat tidak mengganti password yang sudah tersimpan di database.
