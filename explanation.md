# Panduan Lengkap & Penjelasan Mendalam: Zero to Production (API dengan CI/CD, Docker, Terraform, dan Dashboards)

Dokumen ini berisi panduan langkah demi langkah beserta penjelasan teknis mendalam untuk proyek **Zero to Production**. Proyek ini dirancang untuk membawa Anda dari repositori GitHub kosong hingga memiliki layanan API Python siap produksi (*production-ready*) yang:
1. Diuji secara otomatis pada setiap *Pull Request* (PR).
2. Dibangun menjadi *container image* pada setiap *merge* ke *branch* `main`.
3. Di-*deploy* secara otomatis oleh *pipeline* CI/CD ke infrastruktur AWS yang didefinisikan menggunakan **Terraform**.
4. Dipantau secara *real-time* menggunakan **Prometheus** dan **Grafana**.

---

## Gambaran Umum (*Overview*)

### Apa yang Akan Anda Miliki di Akhir Proyek?
Sebuah repositori GitHub publik yang layak ditunjukkan saat wawancara kerja (*interview*):
- Layanan **FastAPI** lengkap dengan *unit test* (`pytest`).
- **Multi-stage Dockerfile** yang menghasilkan *image* ramping dan aman (*non-root user*).
- Pipeline **GitHub Actions** lengkap (*linting*, *testing*, *build*, *push* ke GitHub Container Registry / GHCR, hingga *deployment* otomatis).
- Konfigurasi **Terraform** untuk memprovisikan *instance* EC2 di AWS lengkap dengan *remote state* di S3 dan autentikasi **OIDC** (tanpa perlu menyimpan *access key* statis di GitHub).
- Dashboard **Grafana** dan aturan peringatan (*alerting*) **Prometheus** yang menampilkan laju *request* (*request rate*), latensi (*p95 latency*), rasio *error*, dan penggunaan CPU dari layanan *live*.
- Perintah untuk menghancurkan (*tear down*) seluruh infrastruktur agar tidak memakan biaya setelah selesai bereksperimen.

### Sebelum Anda Memulai (*Prerequisites*)
- **Akun GitHub dan Akun AWS**: *Free tier* pada akun AWS baru mencakup seluruh layanan yang digunakan di proyek ini. Jika Anda langsung menghapusnya (*tear down*) dalam beberapa hari, biayanya diperkirakan di bawah $1.
- **Kenyamanan Menggunakan Terminal**: Memahami perintah dasar seperti `cd`, `ls`, dan mengedit file.
- **Spesifikasi Perangkat**: Laptop dengan macOS, Windows 10/11, atau Ubuntu Linux dengan ruang penyimpanan kosong sekitar **10 GB** untuk menyimpan *Docker images*.
- **Tidak Perlu Pengalaman Sebelumnya** dengan Docker, Terraform, atau AWS — setiap konsep akan dijelaskan saat digunakan.

### Alat yang Akan Diinstal (*Tools*)
1. **Git & GitHub CLI (`gh`)**: Untuk kontrol versi (*version control*) serta membuat repositori, *Pull Request* (PR), dan mengatur *variables/secrets* langsung dari terminal.
2. **Visual Studio Code (VS Code)**: Editor kode lengkap dengan ekstensi untuk Python, Docker, Terraform, dan GitHub Actions.
3. **Python 3.12**: Bahasa pemrograman untuk membangun layanan FastAPI dan menjalankan pengujian dengan `pytest`.
4. **Docker Desktop (atau Docker Engine di Linux)**: Untuk membangun dan menjalankan *container image* secara lokal, persis seperti yang akan berjalan di server produksi.
5. **Terraform 1.10+**: Alat *Infrastructure as Code* (IaC) untuk mendefinisikan infrastruktur AWS. Versi 1.10 ke atas mendukung *S3-native state locking* (`use_lockfile = true`) sehingga tidak memerlukan tabel DynamoDB tambahan.
6. **AWS CLI v2**: Untuk melakukan *bootstrapping* bucket S3 penyimpanan *state* Terraform dan memverifikasi *resource* yang dibuat di AWS.

### Struktur Repositori Akhir (*Repository Layout*)
```text
zero-to-prod/
├── .github/workflows/
│   ├── ci.yml            # lint + test pada setiap PR
│   ├── release.yml       # build, push ke GHCR, deploy saat merge ke main
│   └── infra.yml         # terraform plan saat PR, apply saat merge
├── app/
│   ├── __init__.py
│   └── main.py           # Layanan FastAPI dengan endpoint /health dan /metrics
├── tests/
│   └── test_main.py      # Pengujian otomatis menggunakan TestClient
├── infra/
│   ├── main.tf           # EC2 host, security group, IAM role untuk SSM
│   ├── variables.tf      # Definisi variabel input Terraform
│   ├── outputs.tf        # Output IP publik dan URL layanan
│   ├── backend.tf        # Konfigurasi remote state di S3
│   └── user_data.sh      # Script yang menginstal Docker & menyalakan stack saat boot
├── deploy/
│   ├── compose.yml       # app + prometheus + grafana + node-exporter
│   ├── prometheus.yml    # Konfigurasi target scraping Prometheus
│   ├── alerts.yml        # Aturan alert (HighErrorRatio & AppDown)
│   └── grafana/          # Provisioning otomatis datasource + dashboard JSON
├── Dockerfile
├── .dockerignore
├── .gitignore
├── pyproject.toml
├── requirements.txt
└── README.md
```

---

## Phase 1: Install the Tools (Instalasi Peralatan)

Tujuan dari fase pertama ini adalah memastikan seluruh *toolchain* terinstal dan terverifikasi sebelum kita menulis satu baris kode pun, sehingga fase-fase berikutnya berjalan lancar tanpa kendala lingkungan (*environment*).

### Langkah 1.1 — Instal Git, GitHub CLI, Python 3.12, Terraform, dan AWS CLI
Pada macOS, gunakan *package manager* Homebrew (instal terlebih dahulu dari `brew.sh` jika belum ada):

```bash
brew install git gh python@3.12 hashicorp/tap/terraform awscli
```

**Penjelasan untuk Sistem Operasi Lain:**
- **Windows**: Buka PowerShell dan jalankan:
  `winget install Git.Git GitHub.cli Python.Python.3.12 Hashicorp.Terraform Amazon.AWSCLI`
- **Ubuntu/Debian Linux**: Jalankan `sudo apt install git python3.12 python3.12-venv`, kemudian ikuti panduan repositori resmi masing-masing vendor untuk menginstal `gh`, `terraform`, dan `awscli` (karena repositori resmi vendor menyediakan versi yang jauh lebih baru daripada repositori bawaan Ubuntu).

### Langkah 1.2 — Instal Docker
- **macOS & Windows**: Unduh dan instal **Docker Desktop** dari `docker.com`, lalu jalankan aplikasinya minimal satu kali agar *Docker daemon* aktif di latar belakang.
- **Ubuntu Linux**: Instal **Docker Engine** menggunakan *convenience script* resmi dan tambahkan akun pengguna Anda ke grup `docker` agar bisa menjalankan perintah `docker` tanpa `sudo`. Setelah itu, *log out* dan *log in* kembali (atau jalankan `newgrp docker`).

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"
```

**Penjelasan Perintah:**
- `curl -fsSL https://get.docker.com | sh`: Mengunduh skrip instalasi resmi Docker dan langsung mengeksekusinya. Flag `-fsSL` memastikan `curl` gagal secara diam-diam jika terjadi *error* HTTP (`-f`), menyembunyikan *progress bar* (`-sS`), dan mengikuti *redirect* (`-L`).
- `sudo usermod -aG docker "$USER"`: Menambahkan *user* aktif saat ini ke dalam grup `docker` (`-aG` = *append to group*) agar memiliki izin mengakses *socket* Docker (`/var/run/docker.sock`).

### Langkah 1.3 — Instal Visual Studio Code beserta Ekstensinya
Instal VS Code, kemudian tambahkan ekstensi pendukung untuk Python, Docker, HashiCorp Terraform, dan GitHub Actions langsung dari terminal:

```bash
code --install-extension ms-python.python
code --install-extension ms-azuretools.vscode-docker
code --install-extension hashicorp.terraform
code --install-extension github.vscode-github-actions
```

> **Catatan macOS:** Jika perintah `code` tidak ditemukan di terminal, buka aplikasi VS Code, tekan `Cmd+Shift+P`, lalu ketik dan jalankan **"Shell Command: Install 'code' command in PATH"**.

### Langkah 1.4 — Verifikasi Versi Seluruh Alat
Pastikan setiap alat berhasil mencetak versinya masing-masing. Jika ada yang gagal, perbaiki sekarang sebelum lanjut ke tahap berikutnya.

```bash
git --version
gh --version
python3.12 --version
docker --version && docker compose version
terraform -version
aws --version
```

**Cara Cek (*Check*):**
Pastikan muncul enam baris versi tanpa pesan *"command not found"*. Khusus untuk **Terraform**, pastikan versinya adalah **1.10 atau lebih baru** karena kita akan menggunakan fitur *S3 lockfile backend* (`use_lockfile = true`) pada Fase 6.

### Langkah 1.5 — Autentikasi GitHub CLI (`gh`)
Hubungkan GitHub CLI ke akun GitHub Anda. Pilih protokol **HTTPS** saat ditanya, dan izinkan `gh` mengonfigurasi kredensial Git untuk Anda.

```bash
gh auth login
gh auth status
```

**Penjelasan:**
- `gh auth login` membuka alur autentikasi interaktif (biasanya melalui *browser* dengan kode satu kali pakai).
- `gh auth status` memverifikasi status sesi login Anda.
- **Cara Cek (*Check*):** Output `gh auth status` menampilkan pesan `"Logged in to github.com"`.

### Langkah 1.6 — Konfigurasi Kredensial AWS CLI
Buat *AWS Access Key* untuk IAM User Anda melalui AWS Console (**IAM → Users → nama user Anda → Security credentials → Create access key → Command Line Interface**), lalu konfigurasikan AWS CLI di laptop Anda. Pilih satu *region* dan gunakan secara konsisten di sepanjang proyek (panduan ini menggunakan `eu-west-1`, Anda bisa menggantinya secara konsisten jika memilih *region* lain).

```bash
aws configure
# AWS Access Key ID:     paste it
# AWS Secret Access Key: paste it
# Default region name:   eu-west-1
# Default output format: json
aws sts get-caller-identity
```

**Penjelasan Penting:**
- Kredensial (*access key*) ini **hanya digunakan untuk tahap *bootstrapping* awal dari laptop Anda** (seperti membuat bucket S3 dan IAM Role).
- Pipeline GitHub Actions **tidak akan menggunakan kunci ini**, melainkan akan mengautentikasi diri ke AWS menggunakan token sementara **OIDC (*OpenID Connect*)** pada Fase 7, sesuai praktik keamanan terbaik (*best practice*).
- **Cara Cek (*Check*):** Perintah `aws sts get-caller-identity` mengembalikan objek JSON berisi `Account` (ID akun AWS Anda), `UserId`, dan `Arn`.

---

## Phase 2: Create the Repository (Membuat Repositori)

Pada fase ini kita membuat repositori GitHub publik dengan konfigurasi awal yang rapi, melakukan *commit* pertama di *branch* `main`, serta mengaktifkan aturan proteksi *branch* (*branch protection*).

### Langkah 2.1 — Buat dan Clone Repositori Menggunakan GitHub CLI
Buat repositori langsung dari terminal, *clone* ke komputer lokal, dan masuk ke direktorinya. Repositori ini sengaja dibuat **publik (`--public`)** agar *container image* di GHCR nantinya juga dapat diatur menjadi publik (sehingga server EC2 dapat menarik *image* tanpa perlu menyimpan kredensial login registri), sekaligus menjadi portofolio publik Anda.

```bash
gh repo create zero-to-prod --public --clone --description "FastAPI service with CI/CD, Docker, Terraform and Grafana"
cd zero-to-prod
```

**Penjelasan Flag:**
- `--public`: Membuat repositori dapat diakses publik.
- `--clone`: Secara otomatis menjalankan `git clone` ke folder lokal setelah repositori dibuat di GitHub.
- `--description`: Menambahkan deskripsi singkat pada halaman repositori GitHub.

### Langkah 2.2 — Tambahkan File `.gitignore`
Buat file `.gitignore` untuk mengecualikan file sementara Python, *state* lokal Terraform, serta file konfigurasi editor atau rahasia lokal. **Ingat: File *state* Terraform (`*.tfstate`), variabel lokal (`*.tfvars`), dan `.env` tidak boleh pernah di-*commit* ke Git karena berisiko membocorkan data sensitif/rahasia!**

```text
# Python
__pycache__/
*.pyc
.venv/
.pytest_cache/
.ruff_cache/

# Terraform
infra/.terraform/
infra/*.tfstate
infra/*.tfstate.backup
infra/.terraform.lock.hcl
infra/*.tfvars

# Local secrets and editor files
.env
.DS_Store
.vscode/settings.json
```

**Penjelasan Isi `.gitignore`:**
- `__pycache__/`, `*.pyc`, `.venv/`, `.pytest_cache/`, `.ruff_cache/`: File *bytecode* Python, *virtual environment* lokal, serta *cache* dari alat pengujian dan *linter*.
- `infra/.terraform/`: Direktori tempat Terraform mengunduh *binary plugin provider* (ukurannya besar dan diunduh ulang saat `terraform init`).
- `infra/*.tfstate*` & `infra/*.tfvars`: File status infrastruktur dan nilai variabel rahasia (seperti *password* Grafana).
- `.env`: File variabel lingkungan lokal.

### Langkah 2.3 — Buat File `README.md` Awal
Tulis dokumentasi `README.md` sejak awal dan perbarui seiring berjalannya proyek. Repositori yang memiliki `README.md` jelas tentang cara menjalankannya adalah pembeda utama antara sekadar "kumpulan folder" dan "proyek rekayasa perangkat lunak yang matang".

```text
# zero-to-prod

A small FastAPI service taken all the way to production:
tests on every PR, container image on every merge, Terraform-managed AWS host,
Prometheus + Grafana dashboards.

## Run locally

    python3.12 -m venv .venv && source .venv/bin/activate
    pip install -r requirements.txt
    uvicorn app.main:app --reload

Then open http://localhost:8000/docs
```

### Langkah 2.4 — Buka di VS Code dan Lakukan Commit Pertama
Buka direktori proyek di VS Code, tambahkan file ke *staging area*, buat *commit* pertama, dan *push* ke *branch* `main` di GitHub.

```bash
code .
git add .gitignore README.md
git commit -m "chore: repository skeleton"
git push -u origin main
```

**Cara Cek (*Check*):** Buka halaman repositori Anda di GitHub dan pastikan tampilan `README.md` sudah muncul dengan rapi.

### Langkah 2.5 — Aktifkan Proteksi Branch `main` (*Branch Protection*)
Lindungi *branch* `main` agar tidak ada perubahan kode yang bisa langsung masuk tanpa melalui *Pull Request* dan pemeriksaan CI yang lolos (*green checks*). Inilah yang membuat *pipeline* CI/CD benar-benar bermakna.

```bash
gh api -X PUT "repos/{owner}/zero-to-prod/branches/main/protection" \
  --input - <<'JSON'
{
  "required_status_checks": {"strict": true, "contexts": []},
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
```

**Penjelasan Konfigurasi API GitHub:**
- `{owner}`: Akan diisi secara otomatis oleh `gh` sesuai dengan *username* GitHub Anda.
- `"required_status_checks": {"strict": true, "contexts": []}`: Mewajibkan *branch* PR selalu mutakhir (*up-to-date*) dengan `main` sebelum di-*merge* (`strict: true`). Daftar `contexts` sengaja dikosongkan sementara dan akan diisi dengan nama *job* CI (`test`) pada Fase 5 setelah *workflow*-nya dibuat.
- `"required_pull_request_reviews": null`: Tidak mewajibkan *approval* dari orang lain karena Anda mengerjakan proyek ini sendiri (dalam tim kerja nyata, biasanya diwajibkan minimal 1 *reviewer*).
- `"allow_force_pushes": false` & `"allow_deletions": false`: Mencegah siapa pun melakukan `git push --force` atau menghapus *branch* `main`.

---

## Phase 3: Build the API (Membangun Layanan API)

Pada fase ini kita akan membangun layanan berbasis **FastAPI** yang memiliki tiga *endpoint* utama: `/` (halaman utama), `/health` (untuk pemeriksaan kesehatan aplikasi / *health check*), dan `/metrics` (untuk diekspos ke Prometheus). Seluruh pengembangan dilakukan pada *feature branch* dan digabungkan (*merge*) ke `main` melalui *Pull Request*.

### Langkah 3.1 — Buat Feature Branch Baru
Mulai dari titik ini dan seterusnya, semua pekerjaan dilakukan di dalam *branch* terpisah dan hanya masuk ke `main` melalui *Pull Request* (PR).

```bash
git switch -c feat/api
```

**Penjelasan:** Perintah `git switch -c feat/api` membuat *branch* baru bernama `feat/api` dan langsung berpindah ke *branch* tersebut.

### Langkah 3.2 — Buat Virtual Environment dan Deklarasikan Dependensi
Buat dan aktifkan *virtual environment* Python, kemudian definisikan dependensi aplikasi beserta dependensi pengembangan (*development dependencies*). Mengunci versi secara spesifik (*pinning exact versions*) memastikan *build* selalu dapat direproduksi (*reproducible*) kapan pun dan di mana pun; kombinasi versi di bawah ini sudah teruji kompatibel satu sama lain.

```bash
python3.12 -m venv .venv
source .venv/bin/activate
cat > requirements.txt <<'EOF'
fastapi==0.115.6
uvicorn[standard]==0.34.0
prometheus-fastapi-instrumentator==7.0.0
EOF
cat > requirements-dev.txt <<'EOF'
-r requirements.txt
pytest==8.3.4
httpx==0.28.1
ruff==0.8.4
EOF
pip install -r requirements-dev.txt
```

**Penjelasan Dependensi:**
- **Di dalam `requirements.txt` (Dependensi Produksi):**
  - `fastapi==0.115.6`: Kerangka kerja (*framework*) web modern dan cepat untuk membangun API di Python.
  - `uvicorn[standard]==0.34.0`: Server ASGI berkinerja tinggi untuk menjalankan aplikasi FastAPI di produksi.
  - `prometheus-fastapi-instrumentator==7.0.0`: *Middleware* otomatis yang mengukur metrik HTTP (jumlah *request*, durasi/latensi, ukuran *response*, status kode HTTP) pada FastAPI dan menyajikannya dalam format Prometheus.
- **Di dalam `requirements-dev.txt` (Dependensi Pengembangan & CI):**
  - `-r requirements.txt`: Menyertakan seluruh paket dari `requirements.txt` agar tidak terjadi duplikasi daftar.
  - `pytest==8.3.4`: Kerangka kerja untuk menjalankan pengujian otomatis (*unit testing*).
  - `httpx==0.28.1`: Pustaka HTTP klien yang dibutuhkan oleh `fastapi.testclient.TestClient` untuk menyimulasikan *request* ke aplikasi tanpa harus menyalakan server sungguhan.
  - `ruff==0.8.4`: *Linter* dan *code formatter* Python super cepat (ditulis dengan Rust) untuk menjaga kualitas dan kerapian kode.
- **Catatan Windows:** Jika menggunakan Windows PowerShell, aktifkan *virtualenv* dengan perintah `.venv\Scripts\Activate.ps1`. Jika VS Code menawarkan untuk menggunakan *interpreter* dari `.venv` ini, klik **Accept/Yes**.

### Langkah 3.3 — Tulis Kode Aplikasi FastAPI (`app/main.py`)
Buat kode aplikasi di `app/main.py`. Aplikasi ini mengekspos:
1. `GET /`: Mengembalikan pesan sapaan yang dibaca dari *environment variable* `GREETING` (mengikuti prinsip *Twelve-Factor App* di mana konfigurasi dipisahkan dari kode).
2. `GET /health`: Digunakan oleh Docker *healthcheck* atau *load balancer* untuk memastikan aplikasi hidup.
3. `GET /metrics`: Diekspos secara otomatis oleh `Instrumentator` untuk di-*scrape* oleh Prometheus.

Jangan lupa buat juga file kosong `app/__init__.py` dengan perintah `touch app/__init__.py` agar direktori `app` dikenali sebagai paket (*package*) Python.

```python
# app/main.py
import os

from fastapi import FastAPI
from prometheus_fastapi_instrumentator import Instrumentator

app = FastAPI(title="zero-to-prod")
Instrumentator().instrument(app).expose(app, endpoint="/metrics")


@app.get("/")
def root():
    return {"message": os.environ.get("GREETING", "hello from zero-to-prod")}


@app.get("/health")
def health():
    return {"status": "ok"}
```

**Penjelasan Kode:**
- `Instrumentator().instrument(app).expose(app, endpoint="/metrics")`: Mengaitkan *middleware* pencatat metrik ke objek `app` dan mendaftarkan *route* `/metrics` yang menghasilkan teks metrik berformat Prometheus.
- `os.environ.get("GREETING", "hello from zero-to-prod")`: Mengambil nilai variabel lingkungan `GREETING`. Jika tidak disetel, aplikasi akan menggunakan nilai bawaan (*default*) `"hello from zero-to-prod"`.

### Langkah 3.4 — Jalankan Secara Lokal dan Uji Endpoint-nya
Jalankan server lokal dengan fitur *auto-reload*, lalu uji *endpoint* `/health` dan `/metrics` dari terminal lain (atau buka dokumentasi interaktif Swagger UI di `http://localhost:8000/docs`).

```bash
uvicorn app.main:app --reload
# in another terminal:
curl -s localhost:8000/health
curl -s localhost:8000/metrics | head -5
```

**Cara Cek (*Check*):**
- `curl -s localhost:8000/health` mengembalikan JSON `{"status":"ok"}`.
- `curl -s localhost:8000/metrics | head -5` mencetak baris-baris teks metrik Prometheus yang diawali dengan `# HELP`.

### Langkah 3.5 — Tambahkan Unit Tests (`tests/test_main.py`)
Buat pengujian otomatis di dalam `tests/test_main.py`. Pengujian ini menggunakan `TestClient` bawaan FastAPI, sehingga dapat dijalankan secara langsung di memori tanpa perlu menyalakan server Uvicorn terlebih dahulu.

```python
# tests/test_main.py
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_root_returns_default_greeting():
    r = client.get("/")
    assert r.status_code == 200
    assert "message" in r.json()


def test_health():
    assert client.get("/health").json() == {"status": "ok"}


def test_metrics_exposed():
    r = client.get("/metrics")
    assert r.status_code == 200
    assert "http_requests_total" in r.text
```

**Penjelasan Pengujian:**
1. `test_root_returns_default_greeting()`: Memastikan `GET /` mengembalikan kode status HTTP `200 OK` dan memiliki kunci `"message"` di dalam *payload* JSON-nya.
2. `test_health()`: Memastikan `GET /health` mengembalikan `{"status": "ok"}`.
3. `test_metrics_exposed()`: Memastikan `GET /metrics` mengembalikan kode status `200 OK` dan memuat metrik penghitung `http_requests_total`. Karena fungsi tes ini dijalankan setelah dua tes sebelumnya, penghitung *request* sudah terisi dan metrik `http_requests_total` dijamin sudah terbentuk.

### Langkah 3.6 — Konfigurasi Ruff dan Pytest di `pyproject.toml`
Buat file `pyproject.toml` di akar (*root*) repositori untuk mengatur konfigurasi *linter/formatter* `ruff` dan `pytest`, lalu jalankan keduanya.

```toml
[tool.ruff]
line-length = 100
target-version = "py312"

[tool.ruff.lint]
select = ["E", "F", "I", "B"]

[tool.pytest.ini_options]
testpaths = ["tests"]
```

**Penjelasan Konfigurasi `pyproject.toml`:**
- `line-length = 100`: Mengizinkan panjang baris kode hingga 100 karakter sebelum dianggap terlalu panjang.
- `target-version = "py312"`: Memberitahu Ruff agar memvalidasi sintaks berdasarkan standar Python 3.12.
- `select = ["E", "F", "I", "B"]`: Mengaktifkan aturan pemeriksaan untuk:
  - `E` (*pycodestyle errors* — standar gaya penulisan PEP 8),
  - `F` (*Pyflakes* — mendeteksi variabel/impor yang tidak terpakai atau kesalahan logika dasar),
  - `I` (*isort* — memastikan urutan `import` rapi dan terurut alfabetis),
  - `B` (*flake8-bugbear* — mendeteksi potensi *bug* umum dan pola desain yang buruk di Python).
- `testpaths = ["tests"]`: Menginstruksikan `pytest` untuk mencari file pengujian di dalam folder `tests/`.

**Cara Cek (*Check*):** Jalankan perintah:
`ruff check . && ruff format --check . && pytest -q`
Pastikan ke-3 tes lolos (*3 passed*) dan tidak ada satupun *error* dari *linter* maupun *formatter*.

### Langkah 3.7 — Commit, Push, Buat PR, dan Merge ke `main`
Simpan perubahan ke dalam Git di *branch* `feat/api`, *push* ke GitHub, buat *Pull Request*, tinjau perubahan (*diff*) di GitHub layaknya seorang *code reviewer*, lalu lakukan *merge*.

```bash
git add .
git commit -m "feat: FastAPI service with health and metrics endpoints"
git push -u origin feat/api
gh pr create --fill
gh pr merge --squash --delete-branch
git switch main && git pull
```

**Penjelasan Flag GitHub CLI:**
- `gh pr create --fill`: Membuat PR secara otomatis dengan mengisi judul dan deskripsi dari pesan *commit*.
- `gh pr merge --squash --delete-branch`: Menggabungkan seluruh *commit* di PR menjadi satu *commit* tunggal yang bersih di *branch* `main` (`--squash`), sekaligus menghapus *branch* `feat/api` baik di GitHub (*remote*) maupun di lokal (`--delete-branch`).

---

## Phase 4: Containerise It (Kontainerisasi & Observabilitas Lokal)

Pada fase ini kita membungkus API ke dalam *Docker image* berukuran kecil yang berjalan sebagai pengguna tanpa hak akses *root* (*non-root user*) demi keamanan. Selain itu, kita juga menyiapkan tumpukan (*stack*) **Docker Compose** lokal yang menjalankan aplikasi bersama **Prometheus**, **Node Exporter**, dan **Grafana** agar kita dapat melihat metrik dan grafik secara lokal sebelum menyentuh *cloud* AWS.

### Langkah 4.1 — Buat Branch Baru untuk Docker
Mulai dengan membuat *branch* fitur baru bernama `feat/docker`:

```bash
git switch -c feat/docker
```

### Langkah 4.2 — Buat Multi-Stage `Dockerfile`
Buat file `Dockerfile` dengan teknik **Multi-Stage Build**. Tahap pertama (`build`) bertugas membuat *virtual environment* dan menginstal dependensi; tahap kedua (tahap akhir) hanya menyalin *virtual environment* yang sudah jadi beserta kode aplikasi, lalu menjalankannya sebagai pengguna biasa tanpa hak akses administrator (*unprivileged user*).

```dockerfile
# syntax=docker/dockerfile:1
FROM python:3.12-slim AS build
WORKDIR /src
COPY requirements.txt .
RUN python -m venv /venv && /venv/bin/pip install --no-cache-dir -r requirements.txt

FROM python:3.12-slim
RUN useradd --create-home --uid 10001 app
WORKDIR /home/app
COPY --from=build /venv /venv
COPY app ./app
ENV PATH="/venv/bin:$PATH" PYTHONUNBUFFERED=1
USER app
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')"
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

**Penjelasan Baris demi Baris `Dockerfile`:**
- `FROM python:3.12-slim AS build`: Menggunakan *base image* varian `slim` (berbasis Debian minimal) untuk tahap *build*.
- `COPY requirements.txt .` diikuti `RUN ... pip install`: Menyalin `requirements.txt` lebih dulu sebelum kode aplikasi agar Docker dapat memanfaatkan *layer caching* — jika kode di `app/` berubah tetapi `requirements.txt` tidak berubah, Docker tidak perlu mengunduh ulang paket `pip`.
- `--no-cache-dir`: Mencegah `pip` menyimpan *cache* unduhan di dalam *image* agar ukuran tetap kecil.
- `RUN useradd --create-home --uid 10001 app` & `USER app`: Membuat pengguna dengan UID `10001` (di atas 10000 agar tidak bentrok dengan UID sistem pada *host* Linux) dan menjalankan aplikasi sebagai *user* tersebut. Jika aplikasi berhasil diretas, penyerang tidak memiliki akses `root` di dalam kontainer.
- `COPY --from=build /venv /venv`: Hanya menyalin folder `/venv` dari tahap pertama ke tahap akhir.
- `ENV PATH="/venv/bin:$PATH" PYTHONUNBUFFERED=1`: Menambahkan `/venv/bin` ke `PATH` agar perintah `python` dan `uvicorn` langsung mengarah ke *virtualenv*, serta menyetel `PYTHONUNBUFFERED=1` agar *log* `stdout`/`stderr` langsung tercetak ke `docker logs` secara *real-time* tanpa tertahan di *buffer*.
- `HEALTHCHECK ...`: Menginstruksikan Docker untuk memeriksa `/health` setiap 30 detik menggunakan pustaka bawaan Python `urllib.request` (karena `curl` tidak terinstal di dalam *image* `slim` demi menghemat ukuran dan memperkecil celah keamanan).

### Langkah 4.3 — Tambahkan File `.dockerignore`
Buat file `.dockerignore` agar *build context* yang dikirim ke *Docker daemon* tetap kecil dan cepat, sekaligus memastikan file rahasia seperti `.env` atau folder `.git` tidak pernah masuk ke dalam lapisan (*layer*) *image*.

```text
.git
.venv
.github
infra
deploy
tests
__pycache__
*.pyc
.env
.pytest_cache
.ruff_cache
README.md
```

### Langkah 4.4 — Bangun dan Uji Container Image Secara Lokal
Bangun (*build*) *image* Docker dengan *tag* `zero-to-prod:dev`, jalankan kontainer dengan menyuntikkan variabel lingkungan `GREETING`, lalu uji dari terminal lain.

```bash
docker build -t zero-to-prod:dev .
docker run --rm -p 8000:8000 -e GREETING="hello from a container" zero-to-prod:dev
# another terminal:
curl -s localhost:8000/
```

**Cara Cek (*Check*):**
- Respons dari `curl -s localhost:8000/` menampilkan `"hello from a container"`.
- Jika Anda menjalankan `docker image ls zero-to-prod`, ukuran *image* hanya berkisar sekitar **~150 MB** berkat penggunaan *base image* `slim` dan *multi-stage build*.
- Tekan `Ctrl+C` pada terminal yang menjalankan `docker run` untuk menghentikannya (flag `--rm` akan langsung membersihkan kontainer tersebut).

### Langkah 4.5 — Buat Konfigurasi Docker Compose (`deploy/compose.yml`)
Buat folder `deploy/` dan file `deploy/compose.yml` untuk menjalankan seluruh tumpukan observabilitas lokal yang terdiri dari 4 layanan:
1. `app`: Layanan FastAPI kita.
2. `prometheus`: Mengambil (*scrape*) dan menyimpan data metrik deret waktu (*time-series*) dari `app` dan `node-exporter`.
3. `node-exporter`: Mengekspos metrik perangkat keras dan sistem operasi *host* (seperti penggunaan CPU, RAM, dan disk).
4. `grafana`: Menampilkan visualisasi grafik metrik dari Prometheus ke dalam *dashboard*.

File `deploy/compose.yml` yang sama persis ini nantinya juga akan digunakan di server produksi EC2!

```yaml
# deploy/compose.yml
services:
  app:
    image: ${APP_IMAGE:-zero-to-prod:dev}
    environment:
      GREETING: ${GREETING:-hello from compose}
    ports: ["80:8000"]
    restart: unless-stopped

  prometheus:
    image: prom/prometheus:v3.1.0
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./alerts.yml:/etc/prometheus/alerts.yml:ro
      - prom-data:/prometheus
    ports: ["9090:9090"]
    restart: unless-stopped

  node-exporter:
    image: prom/node-exporter:v1.8.2
    pid: host
    volumes: ["/:/host:ro,rslave"]
    command: ["--path.rootfs=/host"]
    restart: unless-stopped

  grafana:
    image: grafana/grafana:11.4.0
    environment:
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_PASSWORD:-admin}
      GF_USERS_ALLOW_SIGN_UP: "false"
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - ./grafana/dashboards:/var/lib/grafana/dashboards:ro
      - grafana-data:/var/lib/grafana
    ports: ["3000:3000"]
    restart: unless-stopped

volumes:
  prom-data:
  grafana-data:
```

**Penjelasan Teknis `deploy/compose.yml`:**
- `${VAR:-default}`: Sintaks interpolasi variabel lingkungan di Docker Compose. Misalnya `${APP_IMAGE:-zero-to-prod:dev}` berarti: gunakan nilai variabel `APP_IMAGE` dari lingkungan/`.env` jika ada (di server produksi nanti akan diisi dengan `ghcr.io/...`), tetapi jika kosong (seperti saat dijalankan di laptop lokal), gunakan `zero-to-prod:dev`.
- `ports: ["80:8000"]` pada `app`: Memetakan *port* HTTP standar `80` di mesin *host* ke *port* `8000` di dalam kontainer `app`.
- `:ro` pada *volume mounts*: Memasang file konfigurasi dalam mode *read-only* (hanya baca) agar kontainer tidak dapat memodifikasinya.
- `pid: host` dan `volumes: ["/:/host:ro,rslave"]` pada `node-exporter`: Memberikan akses baca ke sistem file dan ruang proses *host* agar `node-exporter` dapat membaca statistik CPU dan memori mesin utama, bukan sekadar kontainernya sendiri.

### Langkah 4.6 — Buat Konfigurasi Prometheus (`deploy/prometheus.yml`)
Beritahu Prometheus layanan mana saja yang harus diambil metriknya (*scrape*). Di dalam jaringan internal Docker Compose, setiap kontainer dapat saling menghubungi cukup dengan memanggil nama layanannya (*service name*) sebagai *hostname* DNS.

```yaml
# deploy/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - /etc/prometheus/alerts.yml

scrape_configs:
  - job_name: app
    static_configs:
      - targets: ["app:8000"]
  - job_name: node
    static_configs:
      - targets: ["node-exporter:9100"]
  - job_name: prometheus
    static_configs:
      - targets: ["localhost:9090"]
```

**Penjelasan:**
- `scrape_interval: 15s`: Prometheus akan mengambil data metrik dari setiap *target* setiap 15 detik sekali.
- `evaluation_interval: 15s`: Prometheus akan mengevaluasi aturan *alert* di `alerts.yml` setiap 15 detik sekali.
- `scrape_configs`: Mendefinisikan tiga *job* pemantauan, yaitu aplikasi FastAPI (`app:8000`), statistik mesin *host* (`node-exporter:9100`), dan kesehatan internal Prometheus itu sendiri (`localhost:9090`).

### Langkah 4.7 — Tambahkan Aturan Alert Prometheus (`deploy/alerts.yml`)
Buat file `deploy/alerts.yml` yang berisi dua aturan peringatan (*alert rules*):
1. **`HighErrorRatio`**: Aktif (*firing*) apabila rasio *error* HTTP `5xx` selama rentang 5 menit terakhir melebihi **5% (`0.05`)** secara terus-menerus selama minimal 2 menit (`for: 2m`).
2. **`AppDown`**: Aktif apabila Prometheus gagal melakukan *scrape* terhadap kontainer `app` (`up{job="app"} == 0`) selama minimal 1 menit (`for: 1m`).

```yaml
# deploy/alerts.yml
groups:
  - name: app
    rules:
      - alert: HighErrorRatio
        expr: |
          sum(rate(http_requests_total{job="app",status=~"5.."}[5m]))
            / sum(rate(http_requests_total{job="app"}[5m])) > 0.05
        for: 2m
        labels:
          severity: page
        annotations:
          summary: "More than 5% of requests are failing"
      - alert: AppDown
        expr: up{job="app"} == 0
        for: 1m
        labels:
          severity: page
        annotations:
          summary: "Prometheus cannot scrape the app"
```

### Langkah 4.8 — Provisioning Datasource Grafana (`deploy/grafana/provisioning/datasources/prometheus.yml`)
Agar kita tidak perlu mengklik dan mengatur koneksi Prometheus secara manual di antarmuka web Grafana setiap kali kontainer dijalankan, kita menggunakan fitur **Grafana Provisioning**. Buat file `deploy/grafana/provisioning/datasources/prometheus.yml`:

```yaml
# deploy/grafana/provisioning/datasources/prometheus.yml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    uid: prometheus
    url: http://prometheus:9090
    isDefault: true
    editable: false
```

### Langkah 4.9 — Provisioning Pembaca Dashboard Grafana (`deploy/grafana/provisioning/dashboards/dashboards.yml`)
Buat file `deploy/grafana/provisioning/dashboards/dashboards.yml` untuk memberitahu Grafana agar secara otomatis memuat seluruh file definisi *dashboard* berformat JSON yang ada di dalam folder `/var/lib/grafana/dashboards`:

```yaml
# deploy/grafana/provisioning/dashboards/dashboards.yml
apiVersion: 1
providers:
  - name: zero-to-prod
    folder: ""
    type: file
    options:
      path: /var/lib/grafana/dashboards
```

### Langkah 4.10 — Buat File JSON Dashboard Grafana (`deploy/grafana/dashboards/zero-to-prod.json`)
Simpan definisi JSON berikut sebagai `deploy/grafana/dashboards/zero-to-prod.json`. Dashboard ini menampilkan 4 panel utama (*Golden Signals*):
1. **Requests / s**: Laju permintaan masuk per detik (`rate(http_requests_total[1m])`).
2. **p95 latency (s)**: Waktu respons persentil ke-95 dalam detik menggunakan fungsi `histogram_quantile(0.95, ...)`.
3. **5xx ratio (5m)**: Persentase *error* server (berwarna hijau jika normal, berubah menjadi merah jika menyentuh ambang batas 5% / `0.05`).
4. **Host CPU busy %**: Persentase kesibukan CPU mesin *host* (100% dikurangi rata-rata persentase CPU dalam mode `idle`).

```json
{
  "title": "zero-to-prod",
  "uid": "zero-to-prod",
  "schemaVersion": 39,
  "refresh": "10s",
  "time": {"from": "now-30m", "to": "now"},
  "panels": [
    {"type": "timeseries", "title": "Requests / s", "gridPos": {"x": 0, "y": 0, "w": 12, "h": 8},
     "targets": [{"expr": "sum(rate(http_requests_total{job=\"app\"}[1m]))", "legendFormat": "rps"}]},
    {"type": "timeseries", "title": "p95 latency (s)", "gridPos": {"x": 12, "y": 0, "w": 12, "h": 8},
     "targets": [{"expr": "histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{job=\"app\"}[5m])) by (le))", "legendFormat": "p95"}]},
    {"type": "stat", "title": "5xx ratio (5m)", "gridPos": {"x": 0, "y": 8, "w": 12, "h": 6},
     "fieldConfig": {"defaults": {"unit": "percentunit", "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "red", "value": 0.05}]}}},
     "targets": [{"expr": "sum(rate(http_requests_total{job=\"app\",status=~\"5..\"}[5m])) / sum(rate(http_requests_total{job=\"app\"}[5m]))"}]},
    {"type": "timeseries", "title": "Host CPU busy %", "gridPos": {"x": 12, "y": 8, "w": 12, "h": 6},
     "targets": [{"expr": "100 - avg(rate(node_cpu_seconds_total{mode=\"idle\"}[2m])) * 100", "legendFormat": "cpu"}]}
  ]
}
```

### Langkah 4.11 — Jalankan Seluruh Stack Secara Lokal dan Hasilkan Traffic
Nyalakan seluruh kontainer di latar belakang (`-d` / *detached mode*) menggunakan Docker Compose, lalu kirimkan 200 *request* ke `localhost` (port 80) agar grafik metrik terisi data.

```bash
cd deploy
docker compose up -d
for i in $(seq 1 200); do curl -s localhost/ > /dev/null; done
cd ..
```

**Cara Cek (*Check*):**
1. Buka `http://localhost:3000` di *browser* dan masuk dengan *username* `admin` dan *password* `admin`. Buka *dashboard* **"zero-to-prod"** dan pastikan grafik garis laju *request* (*Requests / s*) mulai bergerak naik.
2. Buka `http://localhost:9090/alerts` dan pastikan kedua aturan *alert* (`HighErrorRatio` dan `AppDown`) terdaftar dengan status **Inactive** (berwarna hijau).

### Langkah 4.12 — Commit dan Merge Melalui Pull Request
Simpan seluruh file Dockerfile dan konfigurasi observabilitas di `deploy/`, buat PR, dan gabungkan ke `main`.

```bash
git add .
git commit -m "feat: Dockerfile and local compose stack with Prometheus and Grafana"
git push -u origin feat/docker
gh pr create --fill && gh pr merge --squash --delete-branch
git switch main && git pull
```

---

## Phase 5: Continuous Integration (Otomatisasi Pengujian & Pembuatan Image di GitHub Actions)

Pada fase ini kita mengotomatiskan pemeriksaan kualitas kode: setiap *Pull Request* akan di-*lint* dan diuji secara otomatis, sementara setiap *merge* ke *branch* `main` akan membangun *Docker image* dan mengunggahnya (*push*) ke **GitHub Container Registry (GHCR)** lengkap dengan *tag* yang tidak dapat diubah (*immutable tag* berbasis SHA *commit*).

### Langkah 5.1 — Buat Branch dan Direktori Workflow GitHub Actions
Buat *branch* baru bernama `ci/pipeline` dan siapkan direktori `.github/workflows` tempat GitHub Actions membaca definisi *pipeline*.

```bash
git switch -c ci/pipeline
mkdir -p .github/workflows
```

### Langkah 5.2 — Buat Workflow CI (`.github/workflows/ci.yml`)
Buat file `.github/workflows/ci.yml` yang berjalan setiap kali ada *Pull Request* atau *push* ke *branch* `main`. Workflow ini menginstal Python 3.12 beserta *cache* `pip`, menginstal dependensi pengembangan, lalu menjalankan `ruff` dan `pytest`.

```yaml
name: ci

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
          cache: pip
      - run: pip install -r requirements-dev.txt
      - run: ruff check . && ruff format --check .
      - run: pytest -q
```

**Penjelasan Konfigurasi `ci.yml`:**
- `permissions: contents: read`: Menerapkan prinsip *least privilege* (hak akses minimum) — *job* ini hanya butuh izin membaca kode sumber repositori.
- `cache: pip`: Menyimpan *cache* paket yang diunduh oleh `pip` di antara eksekusi *workflow*, sehingga eksekusi CI berikutnya menjadi jauh lebih cepat.
- `ruff check . && ruff format --check .`: Memastikan tidak ada pelanggaran aturan *linting* dan seluruh file Python sudah terformat rapi sesuai standar.

### Langkah 5.3 — Buat Workflow Release (`.github/workflows/release.yml`)
Buat file `.github/workflows/release.yml`. Setiap kali ada *commit* baru di `main` (kecuali perubahan yang hanya menyentuh folder `infra/**` atau `README.md`), *workflow* ini akan membangun *Docker image* satu kali, memberinya dua *tag* (`sha-<7-karakter-commit>` dan `latest`), lalu mengunggahnya ke **GHCR (`ghcr.io`)** menggunakan token bawaan GitHub Actions (`secrets.GITHUB_TOKEN`) — tanpa perlu membuat atau mengelola token rahasia secara manual!

```yaml
name: release

on:
  push:
    branches: [main]
    paths-ignore: ["infra/**", "README.md"]

permissions:
  contents: read
  packages: write
  id-token: write

env:
  IMAGE: ghcr.io/${{ github.repository }}

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      tag: ${{ steps.meta.outputs.tag }}
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - id: meta
        run: echo "tag=sha-${GITHUB_SHA::7}" >> "$GITHUB_OUTPUT"
      - uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: |
            ${{ env.IMAGE }}:${{ steps.meta.outputs.tag }}
            ${{ env.IMAGE }}:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

**Penjelasan Teknis `release.yml`:**
- `paths-ignore: ["infra/**", "README.md"]`: Menghemat waktu dan kuota CI dengan tidak membangun ulang *Docker image* aplikasi jika yang berubah hanyalah kode Terraform atau dokumentasi.
- `permissions`:
  - `packages: write`: Diperlukan agar `GITHUB_TOKEN` diizinkan mengunggah *image* ke GitHub Packages / GHCR.
  - `id-token: write`: Disiapkan untuk Fase 7 agar *job* `deploy` nantinya dapat meminta token OIDC ke AWS.
- `echo "tag=sha-${GITHUB_SHA::7}" >> "$GITHUB_OUTPUT"`: Mengambil 7 karakter pertama dari hash *commit* Git (`GITHUB_SHA`), memformatnya menjadi misalnya `sha-a1b2c3d`, dan menyimpannya ke dalam *output* langkah `meta` (serta *output* dari *job* `build`) agar dapat digunakan oleh *job* `deploy` pada Fase 7.
- `cache-from: type=gha` & `cache-to: type=gha,mode=max`: Memanfaatkan penyimpanan *cache* bawaan GitHub Actions untuk menyimpan semua lapisan (*layers*) *multi-stage build* Docker, sehingga proses *build* berikutnya berjalan sangat singkat.

### Langkah 5.4 — Buka Pull Request dan Pantau Eksekusi CI
*Commit* folder `.github`, *push* ke GitHub, buat PR, dan pantau jalannya *workflow* `ci` langsung dari terminal. Jika ada yang merah (*failed*), perbaiki terlebih dahulu sebelum melakukan *merge*.

```bash
git add .github
git commit -m "ci: lint and test on PRs, build and push image on main"
git push -u origin ci/pipeline
gh pr create --fill
gh pr checks --watch
```

**Cara Cek (*Check*):** Perintah `gh pr checks --watch` selesai dengan menampilkan status *job* `test` yang berhasil (**pass**).

### Langkah 5.5 — Jadikan Check `test` Wajib (Required) pada Branch `main`, Lalu Merge
Sekarang setelah *job* `test` dikenal oleh GitHub, perbarui aturan *branch protection* pada `main` agar mewajibkan *status check* `test` lulus sebelum PR mana pun dapat digabungkan. Setelah itu, lakukan *merge* dan pantau jalannya *workflow* `release`.

```bash
gh api -X PATCH "repos/{owner}/zero-to-prod/branches/main/protection/required_status_checks" \
  -f strict=true -f 'contexts[]=test'
gh pr merge --squash --delete-branch
git switch main && git pull
gh run watch
```

**Cara Cek (*Check*):**
- Eksekusi *workflow* `release` yang dipantau lewat `gh run watch` selesai dengan warna hijau (*success*).
- Buka halaman profil GitHub Anda → tab **Packages**, dan pastikan paket **zero-to-prod** sudah muncul lengkap dengan *tag* `latest` dan `sha-…`.

### Langkah 5.6 — Ubah Visibilitas Paket GHCR Menjadi Publik
Secara bawaan (*default*), paket baru di GHCR bersifat privat meskipun repositorinya publik. Agar server EC2 kita dapat menarik (*pull*) *image* tanpa perlu menyimpan kredensial/token GitHub di server, ubah visibilitasnya menjadi **Public**:
1. Di GitHub, buka halaman paket **zero-to-prod** Anda.
2. Klik **Package settings** (di pojok kanan bawah).
3. Gulir ke bagian **Danger Zone** → klik **Change visibility** → pilih **Public**.
4. Konfirmasi dari laptop Anda dengan keluar (*logout*) dari `ghcr.io` lalu mencoba melakukan `docker pull` tanpa login:

```bash
docker logout ghcr.io
docker pull ghcr.io/YOUR_GITHUB_USER/zero-to-prod:latest
```

*(Ganti `YOUR_GITHUB_USER` dengan username GitHub Anda).*
**Cara Cek (*Check*):** Perintah `docker pull` berhasil mengunduh *image* meskipun dalam keadaan *logged out*.

---

## Phase 6: Infrastructure as Code (Memprovisikan Server AWS dengan Terraform)

Pada fase ini kita mendefinisikan server **Amazon EC2** menggunakan **Terraform**, dengan penyimpanan *state* terpusat (*remote state*) di **Amazon S3** dan **tanpa membuka port SSH (port 22) sama sekali**. Sebagai ganti SSH, *instance* EC2 dikelola secara aman menggunakan **AWS Systems Manager (SSM)**, dan secara otomatis menyalakan tumpukan Docker Compose saat pertama kali menyala (*boot*).

### Langkah 6.1 — Buat S3 Bucket untuk Menyimpan State Terraform
Buat *bucket* S3 yang akan menyimpan file *state* Terraform (`terraform.tfstate`). Karena nama *bucket* S3 harus unik di seluruh dunia (*globally unique*), kita menyertakan nomor ID akun AWS Anda di dalam namanya. Kita juga mengaktifkan fitur **Versioning** agar Anda selalu bisa memulihkan versi *state* sebelumnya jika terjadi kesalahan.

```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
aws s3api create-bucket --bucket "tfstate-zero-to-prod-$ACCOUNT" --region eu-west-1 \
  --create-bucket-configuration LocationConstraint=eu-west-1
aws s3api put-bucket-versioning --bucket "tfstate-zero-to-prod-$ACCOUNT" \
  --versioning-configuration Status=Enabled
echo "tfstate-zero-to-prod-$ACCOUNT"
```

> **Catatan Penting Mengenai Region AWS:** Jika Anda memilih region `us-east-1`, hapus flag `--create-bucket-configuration LocationConstraint=...` karena region `us-east-1` merupakan region *default* global S3 dan akan menolak parameter `LocationConstraint`. Simpan nama *bucket* yang tercetak di layar karena akan digunakan pada Langkah 6.3.

### Langkah 6.2 — Buat Branch Baru dan Folder `infra/`
Buat *branch* `infra/ec2` dan direktori `infra` untuk menyimpan seluruh file konfigurasi Terraform:

```bash
git switch -c infra/ec2
mkdir -p infra
```

### Langkah 6.3 — Buat Konfigurasi Backend & Provider (`infra/backend.tf`)
Buat file `infra/backend.tf` dan ganti `tfstate-zero-to-prod-123456789012` dengan nama *bucket* S3 yang Anda buat pada Langkah 6.1. Sejak **Terraform 1.10+**, fitur `use_lockfile = true` memungkinkan Terraform mengunci *state* menggunakan file `.tflock` langsung di dalam *bucket* S3 yang sama, sehingga kita tidak perlu lagi membuat tabel DynamoDB terpisah untuk *state locking*!

```hcl
terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket       = "tfstate-zero-to-prod-123456789012"
    key          = "ec2/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

provider "aws" {
  region = var.region
}
```

### Langkah 6.4 — Deklarasikan Variabel Input (`infra/variables.tf`)
Buat file `infra/variables.tf` untuk mendefinisikan parameter-parameter yang dibutuhkan oleh konfigurasi infrastruktur kita:

```hcl
# infra/variables.tf
variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "name" {
  type    = string
  default = "zero-to-prod"
}

variable "image" {
  description = "Container image to run, e.g. ghcr.io/you/zero-to-prod:latest"
  type        = string
}

variable "grafana_password" {
  type      = string
  sensitive = true
}

variable "my_ip" {
  description = "Your public IP in CIDR form; Grafana and Prometheus are only reachable from here"
  type        = string
}
```

**Penjelasan Variabel:**
- `sensitive = true` pada `grafana_password`: Mencegah Terraform menampilkan kata sandi Grafana secara terbuka di dalam *log* konsol saat menjalankan `terraform plan` atau `terraform apply`.
- `my_ip`: Alamat IP publik koneksi internet Anda dalam notasi CIDR (misalnya `203.0.113.5/32`) agar *port* antarmuka admin Grafana (`3000`) dan Prometheus (`9090`) hanya bisa diakses oleh Anda sendiri, sementara aplikasi utama di *port* `80` terbuka untuk publik (`0.0.0.0/0`).

### Langkah 6.5 — Tulis Konfigurasi Infrastruktur Utama (`infra/main.tf`)
Buat file `infra/main.tf` yang mendefinisikan:
1. **Data Sources (`data`)**: Mengambil informasi VPC bawaan (*default VPC*), daftar *subnet*-nya, serta ID AMI (*Amazon Machine Image*) terbaru untuk sistem operasi **Amazon Linux 2023** melalui AWS SSM Parameter Store.
2. **Security Group (`aws_security_group.app`)**: Firewall virtual yang mengizinkan trafik masuk (*ingress*) pada *port* `80` dari mana saja (`0.0.0.0/0`), serta *port* `3000` (Grafana) dan `9090` (Prometheus) khusus dari IP Anda (`var.my_ip`). Tidak ada *port* `22` (SSH) yang dibuka!
3. **IAM Role & Instance Profile (`aws_iam_role.instance`)**: Memberikan izin resmi `AmazonSSMManagedInstanceCore` kepada *instance* EC2 agar agen SSM di dalamnya dapat berkomunikasi dengan layanan AWS Systems Manager.
4. **EC2 Instance (`aws_instance.app`)**: Mesin virtual berukuran `t3.micro` (termasuk dalam *AWS Free Tier*) dengan penyimpanan disk 16 GB dan skrip inisialisasi `user_data.sh`.
5. **Elastic IP (`aws_eip.app`)**: Alamat IP publik statis yang dikaitkan ke *instance* EC2 agar IP tidak berubah-ubah.

```hcl
# infra/main.tf
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_security_group" "app" {
  name        = var.name
  description = "web in, admin UIs only from my IP"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "instance" {
  name = "${var.name}-instance"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name}-instance"
  role = aws_iam_role.instance.name
}

resource "aws_instance" "app" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t3.micro"
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name

  user_data = templatefile("${path.module}/user_data.sh", {
    image            = var.image
    grafana_password = var.grafana_password
  })
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 16
  }

  tags = { Name = var.name }
}

resource "aws_eip" "app" {
  instance = aws_instance.app.id
  tags     = { Name = var.name }
}
```

### Langkah 6.6 — Buat Skrip Booting Server (`infra/user_data.sh`)
Buat file `infra/user_data.sh` dan **ganti `YOUR_GITHUB_USER` dengan username GitHub Anda**. Skrip ini dijalankan secara otomatis sebagai `root` oleh `cloud-init` saat *instance* EC2 pertama kali menyala:
1. Menginstal `docker` dan `git` melalui manajer paket `dnf` (Amazon Linux 2023).
2. Menyalakan layanan `docker` dan mengunduh *plugin* resmi `docker compose` v2.32.4.
3. Melakukan `git clone` repositori publik Anda ke `/opt/src` dan menyalin isi folder `deploy/` ke `/opt/app/`.
4. Menulis file `/opt/app/.env` dengan nilai `${image}` dan `${grafana_password}` yang disuntikkan oleh fungsi `templatefile()` Terraform.
5. Menjalankan `docker compose up -d` di dalam `/opt/app`.

```bash
#!/bin/bash
set -euxo pipefail
dnf install -y docker git
systemctl enable --now docker
mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL "https://github.com/docker/compose/releases/download/v2.32.4/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

rm -rf /opt/src && git clone --depth 1 https://github.com/YOUR_GITHUB_USER/zero-to-prod.git /opt/src
mkdir -p /opt/app && cp -r /opt/src/deploy/. /opt/app/
cat > /opt/app/.env <<EOF
APP_IMAGE=${image}
GRAFANA_PASSWORD=${grafana_password}
GREETING=hello from AWS
EOF
cd /opt/app && docker compose up -d
```

> **Catatan Template Terraform:** Karena file ini diproses oleh fungsi `templatefile()` Terraform, ekspresi `${image}` dan `${grafana_password}` akan diisi langsung oleh Terraform sebelum skrip dikirim ke EC2. Jika di masa mendatang Anda ingin menggunakan variabel *shell* dengan kurung kurawal di dalam template Terraform, Anda harus menulisnya dengan tanda dolar ganda `$${VAR}`.

### Langkah 6.7 — Tambahkan Konfigurasi Output (`infra/outputs.tf`)
Buat file `infra/outputs.tf` agar Terraform mencetak alamat IP publik serta tautan URL siap klik ke aplikasi, Grafana, dan Prometheus setiap kali `terraform apply` selesai dijalankan.

```hcl
# infra/outputs.tf
output "public_ip" {
  value = aws_eip.app.public_ip
}

output "urls" {
  value = {
    app        = "http://${aws_eip.app.public_ip}/"
    grafana    = "http://${aws_eip.app.public_ip}:3000/"
    prometheus = "http://${aws_eip.app.public_ip}:9090/"
  }
}
```

### Langkah 6.8 — Buat `terraform.tfvars` Lokal dan Jalankan `terraform apply` Pertama
Buat file `infra/terraform.tfvars` (file ini sudah diabaikan oleh `.gitignore` sehingga aman untuk menyimpan konfigurasi lokal Anda). Ganti `YOUR_GITHUB_USER` dan pilih kata sandi yang kuat untuk `grafana_password`, lalu jalankan inisialisasi, validasi, perencanaan, dan penerapan Terraform dari laptop Anda untuk pertama kalinya.

```bash
cat > infra/terraform.tfvars <<EOF
image            = "ghcr.io/YOUR_GITHUB_USER/zero-to-prod:latest"
grafana_password = "pick-something-long"
my_ip            = "$(curl -s https://checkip.amazonaws.com)/32"
EOF
cd infra
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

**Penjelasan Perintah Terraform:**
- `terraform init`: Menginisialisasi direktori kerja, menghubungkan ke *backend* S3, dan mengunduh *plugin provider* `hashicorp/aws`.
- `terraform fmt`: Merapikan format penulisan file `.tf` secara otomatis sesuai standar resmi HCL.
- `terraform validate`: Memeriksa kebenaran sintaks dan konsistensi tipe data konfigurasi.
- `terraform plan`: Menampilkan pratinjau (*preview*) sumber daya apa saja yang akan dibuat/diubah di AWS.
- `terraform apply`: Menerapkan perubahan secara nyata ke AWS (ketik `yes` saat diminta konfirmasi).

**Cara Cek (*Check*):**
- `terraform plan` menampilkan **6 resources to add**.
- Setelah `terraform apply` selesai, *outputs* akan mencetak alamat IP publik server. Beri waktu sekitar **3 hingga 4 menit** bagi *instance* EC2 untuk menyelesaikan instalasi Docker dan mengunduh *image* kontainer, lalu buka `http://IP_PUBLIK/` di *browser* — pesan sapaan akan menampilkan `"hello from AWS"`.

### Langkah 6.9 — Konfirmasi Manajemen Server Tanpa SSH Menggunakan AWS SSM
Pastikan *instance* EC2 Anda terdaftar sebagai *Online* di AWS Systems Manager, lalu kirimkan perintah jarak jauh melalui **SSM Run Command** untuk memeriksa status kontainer Docker yang berjalan di server — semuanya tanpa kunci SSH maupun *port* 22!

```bash
aws ssm describe-instance-information --query 'InstanceInformationList[].{id:InstanceId,ping:PingStatus}'
INSTANCE=$(aws ec2 describe-instances --filters Name=tag:Name,Values=zero-to-prod Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].InstanceId' --output text)
aws ssm send-command --instance-ids "$INSTANCE" --document-name AWS-RunShellScript \
  --parameters 'commands=["docker ps --format \"{{.Names}} {{.Status}}\""]' --query Command.CommandId --output text
```

**Penjelasan:**
- Jika `PingStatus` belum menampilkan `Online`, tunggu sekitar 1 menit karena agen SSM membutuhkan waktu singkat untuk mendaftarkan diri setelah *instance* selesai *booting*.
- Anda dapat membaca hasil eksekusi perintah tersebut di AWS Console pada menu **Systems Manager → Run Command**, atau melalui CLI menggunakan `aws ssm get-command-invocation --command-id <ID_COMMAND> --instance-id "$INSTANCE"`.
- **Cara Cek (*Check*):** Keempat kontainer (`app`, `prometheus`, `grafana`, `node-exporter`) berstatus **Up**. Buka URL Grafana (`http://IP_PUBLIK:3000/`), login dengan `admin` dan *password* yang Anda atur di `terraform.tfvars`, dan lihat grafik trafik bergerak setelah Anda me-*refresh* halaman utama aplikasi beberapa kali.

### Langkah 6.10 — Commit Kode Infrastruktur dan Merge ke `main`
Kembali ke direktori akar proyek, tambahkan folder `infra`, pastikan dengan `git status` bahwa `terraform.tfvars` maupun `.terraform/` **tidak** ikut masuk ke dalam daftar *staging*, lalu buat *commit*, PR, dan *merge*.

```bash
cd ..
git add infra
git status   # terraform.tfvars and .terraform/ must NOT appear
git commit -m "infra: EC2 host with SSM access, S3 remote state, compose stack on boot"
git push -u origin infra/ec2
gh pr create --fill && gh pr merge --squash --delete-branch
git switch main && git pull
```

---

## Phase 7: Let the Pipeline Own the Infrastructure (Otomatisasi Terraform & Deployment dengan OIDC)

Pada fase ini kita menyerahkan kendali penuh atas infrastruktur dan proses *deployment* aplikasi kepada **GitHub Actions**. Pipeline akan menjalankan `terraform plan` pada *Pull Request*, `terraform apply` saat *merge*, serta men-*deploy* versi *image* terbaru ke EC2. Semuanya dilakukan menggunakan token **OpenID Connect (OIDC)** berumur pendek (*short-lived token*) tanpa pernah menyimpan *AWS Access Key* statis di GitHub!

### Langkah 7.1 — Daftarkan GitHub sebagai OIDC Identity Provider di AWS
Daftarkan `token.actions.githubusercontent.com` sebagai penyedia identitas (*Identity Provider*) di akun AWS Anda (cukup dilakukan satu kali per akun AWS):

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com
```

> **Catatan:** Jika Anda pernah membuatnya sebelumnya di akun AWS yang sama, perintah ini akan menampilkan pesan `EntityAlreadyExists` — itu normal dan aman untuk dilanjutkan.

### Langkah 7.2 — Buat IAM Role dengan Trust Policy Khusus untuk Repositori Anda
Buat IAM Role bernama `github-zero-to-prod` yang **hanya** dapat diasumsikan (*assumed*) oleh *workflow* GitHub Actions yang berasal dari repositori `YOUR_GITHUB_USER/zero-to-prod` milik Anda. **Jangan lupa ganti `YOUR_GITHUB_USER` dengan username GitHub Anda (perhatikan huruf besar/kecilnya)!**

```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
cat > trust.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "arn:aws:iam::$ACCOUNT:oidc-provider/token.actions.githubusercontent.com"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {"token.actions.githubusercontent.com:aud": "sts.amazonaws.com"},
      "StringLike": {"token.actions.githubusercontent.com:sub": "repo:YOUR_GITHUB_USER/zero-to-prod:*"}
    }
  }]
}
EOF
aws iam create-role --role-name github-zero-to-prod --assume-role-policy-document file://trust.json
rm trust.json
```

**Penjelasan Keamanan OIDC (`trust.json`):**
- Saat *workflow* GitHub Actions berjalan, GitHub menerbitkan token JWT bertanda tangan kriptografi yang memuat klaim `sub` (*subject*) berisi `"repo:YOUR_GITHUB_USER/zero-to-prod:ref:refs/heads/main"`.
- Kondisi `"StringLike": {"token.actions.githubusercontent.com:sub": "repo:YOUR_GITHUB_USER/zero-to-prod:*"}` memastikan tidak ada repositori milik orang lain di seluruh GitHub yang bisa meminjam atau menyalahgunakan IAM Role ini!

### Langkah 7.3 — Berikan Izin (Permissions Policy) kepada IAM Role Pipeline
Berikan izin yang dibutuhkan oleh *pipeline* untuk membaca/menulis *state* di S3, mengelola sumber daya EC2, membaca *role* IAM yang sudah ada, serta menjalankan perintah *deployment* melalui SSM Run Command:

```bash
aws iam attach-role-policy --role-name github-zero-to-prod --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
aws iam attach-role-policy --role-name github-zero-to-prod --policy-arn arn:aws:iam::aws:policy/AmazonSSMFullAccess
cat > inline.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {"Effect": "Allow", "Action": ["s3:ListBucket"], "Resource": "arn:aws:s3:::tfstate-zero-to-prod-$ACCOUNT"},
    {"Effect": "Allow", "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], "Resource": "arn:aws:s3:::tfstate-zero-to-prod-$ACCOUNT/*"},
    {"Effect": "Allow", "Action": ["iam:GetRole", "iam:PassRole", "iam:GetInstanceProfile", "iam:ListInstanceProfilesForRole", "iam:ListAttachedRolePolicies", "iam:ListRolePolicies"], "Resource": "*"},
    {"Effect": "Allow", "Action": ["ssm:GetParameter", "ssm:GetParameters"], "Resource": "*"}
  ]
}
EOF
aws iam put-role-policy --role-name github-zero-to-prod --policy-name state-and-deploy --policy-document file://inline.json
rm inline.json
echo "arn:aws:iam::$ACCOUNT:role/github-zero-to-prod"
```

**Penjelasan:**
- Salin ARN Role yang tercetak di baris terakhir (`arn:aws:iam::...:role/github-zero-to-prod`).
- Perhatikan bahwa kita hanya memberikan izin baca IAM (`iam:GetRole`, `iam:PassRole`, dll.) dan tidak memberikan `iam:CreateRole`. Karena IAM Role untuk *instance* EC2 sudah dibuat saat kita menjalankan `terraform apply` pertama kali dari laptop pada Langkah 6.8, *pipeline* CI hanya perlu membaca *state*-nya dan meneruskannya (`iam:PassRole`) ke EC2.

### Langkah 7.4 — Simpan Variables dan Secret di Repositori GitHub
Simpan konfigurasi yang tidak bersifat rahasia sebagai **Repository Variables** (`gh variable set`) dan kata sandi Grafana sebagai **Repository Secret** (`gh secret set`). Pastikan Anda mengganti ARN Role dan *password* sesuai dengan milik Anda:

```bash
gh variable set AWS_ROLE_ARN --body "arn:aws:iam::123456789012:role/github-zero-to-prod"
gh variable set AWS_REGION --body "eu-west-1"
gh variable set MY_IP --body "$(curl -s https://checkip.amazonaws.com)/32"
gh secret set GRAFANA_PASSWORD --body "the-same-password-you-used"
gh variable list && gh secret list
```

### Langkah 7.5 — Buat Branch untuk Workflow Infrastruktur
Buat *branch* baru bernama `ci/infra`:

```bash
git switch -c ci/infra
```

### Langkah 7.6 — Buat Workflow Terraform (`.github/workflows/infra.yml`)
Buat file `.github/workflows/infra.yml`. Workflow ini hanya dipicu ketika ada perubahan di dalam folder `infra/**`:
- Saat ada **Pull Request**, ia menjalankan `terraform fmt -check`, `init`, `validate`, dan `plan`, lalu **menuliskan hasil `terraform plan` sebagai komentar otomatis di halaman PR** agar Anda dapat meninjau dampak perubahan infrastruktur sebelum menyetujui *merge*.
- Saat PR di-**merge ke `main`** (`push`), ia langsung menerapkan perubahan tersebut dengan `terraform apply`.

```yaml
name: infra

on:
  pull_request:
    paths: ["infra/**"]
  push:
    branches: [main]
    paths: ["infra/**"]

permissions:
  contents: read
  id-token: write
  pull-requests: write

env:
  TF_VAR_image: ghcr.io/${{ github.repository }}:latest
  TF_VAR_grafana_password: ${{ secrets.GRAFANA_PASSWORD }}
  TF_VAR_my_ip: ${{ vars.MY_IP }}

jobs:
  terraform:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: infra
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.10.3"
      - run: terraform fmt -check
      - run: terraform init -input=false
      - run: terraform validate
      - id: plan
        run: terraform plan -no-color -input=false -out=tfplan
      - if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            const plan = `${{ steps.plan.outputs.stdout }}`.slice(0, 60000);
            await github.rest.issues.createComment({
              owner: context.repo.owner, repo: context.repo.repo, issue_number: context.issue.number,
              body: '### Terraform plan\n```\n' + plan + '\n```'
            });
      - if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        run: terraform apply -input=false tfplan
```

**Penjelasan Teknis `infra.yml`:**
- `TF_VAR_<nama_variabel>`: Terraform secara otomatis membaca *environment variable* yang diawali dengan `TF_VAR_` untuk mengisi variabel yang dideklarasikan di `variables.tf` (`image`, `grafana_password`, `my_ip`).
- `pull-requests: write`: Izin yang dibutuhkan oleh `actions/github-script@v7` untuk mengirim komentar hasil `plan` ke halaman *Pull Request*.

### Langkah 7.7 — Tambahkan Job `deploy` ke dalam `.github/workflows/release.yml`
Buka file `.github/workflows/release.yml` yang telah kita buat pada Fase 5, lalu tambahkan blok *job* `deploy:` di bagian akhir file (sejajar dengan `build:` di bawah `jobs:`). Setelah *image* selesai dibangun dan diunggah ke GHCR, *job* `deploy` akan memerintahkan *instance* EC2 melalui **AWS SSM Run Command** untuk memperbarui *tag* `APP_IMAGE` di `/opt/app/.env` menjadi *tag* spesifik `sha-…` yang baru saja dibangun, menarik *image* baru, dan menyalakan ulang kontainer `app`.

```yaml
  deploy:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}
      - name: Roll the app to the new image
        run: |
          CMD_ID=$(aws ssm send-command \
            --targets Key=tag:Name,Values=zero-to-prod \
            --document-name AWS-RunShellScript \
            --comment "deploy ${{ needs.build.outputs.tag }}" \
            --parameters 'commands=["cd /opt/app","sed -i s#^APP_IMAGE=.*#APP_IMAGE=${{ env.IMAGE }}:${{ needs.build.outputs.tag }}# .env","docker compose pull app","docker compose up -d app","docker image prune -f"]' \
            --query Command.CommandId --output text)
          echo "command $CMD_ID"
          sleep 20
          aws ssm list-command-invocations --command-id "$CMD_ID" --details \
            --query 'CommandInvocations[].{status:Status,out:CommandPlugins[0].Output}'
```

**Penjelasan Teknis Job `deploy`:**
- `needs: build`: Memastikan `deploy` baru berjalan setelah `build` sukses dan mewarisi `needs.build.outputs.tag` (berupa `sha-xxxxxxx`).
- Mengunci *tag* `sha-…` secara eksplisit di dalam `/opt/app/.env` membuat versi aplikasi yang sedang berjalan di produksi selalu dapat dilacak (*traceable*) tepat ke *commit* Git yang menghasilkannya, sekaligus memudahkan proses *rollback*.
- `docker image prune -f`: Menghapus *image* lama yang sudah tidak terpakai (*dangling/unused images*) agar disk EC2 berukuran 16 GB tidak penuh seiring banyaknya *deployment*.

### Langkah 7.8 — Uji Workflow `infra` dengan Perubahan Kecil di `infra/`
Tambahkan satu baris komentar di akhir `infra/main.tf` agar PR kita memicu jalur eksekusi `infra.yml`, lalu buat PR dan periksa komentar otomatis yang muncul di GitHub.

```bash
printf '\n# Managed by the infra workflow; plan on PR, apply on merge.\n' >> infra/main.tf
git add .github infra
git commit -m "ci: terraform plan/apply and SSM deploy with OIDC"
git push -u origin ci/infra
gh pr create --fill
gh pr checks --watch
```

**Cara Cek (*Check*):** Job `terraform` berhasil (*pass*) dan muncul komentar **"Terraform plan"** pada halaman PR di GitHub yang menyatakan `"No changes. Your infrastructure matches the configuration."` (karena kita hanya menambahkan baris komentar di file `.tf`).

### Langkah 7.9 — Merge PR dan Pantau Eksekusi Apply & Deploy
Gabungkan PR ke `main`, lalu pantau eksekusi *workflow* `infra` dan `release`. Mulai dari titik ini, setiap *merge* ke `main` akan langsung terkirim ke produksi secara otomatis!

```bash
gh pr merge --squash --delete-branch
git switch main && git pull
gh run list --limit 3
gh run watch
```

**Cara Cek (*Check*):** Kedua *workflow* (`infra` dan `release`) selesai dengan warna hijau, dan *log* pada *job* `deploy` menampilkan `"status": "Success"`.

### Langkah 7.10 — Buktikan Siklus End-to-End dengan Perubahan Kode Aplikasi
Mari kita buktikan seluruh siklus *Continuous Deployment* dengan mengubah kode aplikasi di `app/main.py`, menggabungkannya melalui PR, dan menyaksikannya ter-*deploy* ke produksi tanpa campur tangan manual sedikit pun:

```bash
git switch -c feat/greeting
sed -i.bak 's/hello from zero-to-prod/hello from the pipeline/' app/main.py && rm app/main.py.bak
git commit -am "feat: new default greeting"
git push -u origin feat/greeting
gh pr create --fill && gh pr checks --watch && gh pr merge --squash --delete-branch
git switch main && git pull && gh run watch
```

**Penjelasan Konsep Twelve-Factor App:**
- Perhatikan bahwa respons `GET /` di server produksi masih menampilkan `"hello from AWS"`. Mengapa? Karena server produksi menyetel variabel lingkungan `GREETING=hello from AWS` secara eksplisit di dalam `/opt/app/.env`, yang menimpa (*override*) nilai *default* di dalam kode Python (`"hello from the pipeline"`). Inilah wujud nyata prinsip **Twelve-Factor App** (pemisahan konfigurasi lingkungan dari kode sumber).
- Namun jika Anda memeriksa kontainer yang berjalan di server melalui SSM Run Command (`docker ps`), Anda akan melihat *image* yang digunakan sudah berganti ke *tag* `sha-…` dari *commit* terbaru Anda!
- **Cara Cek (*Check*):** Di tab **Actions** pada GitHub, eksekusi *workflow* `release` untuk *merge* tersebut menunjukkan *job* `deploy` berhasil dengan *tag* `sha-…` yang baru.

---

## Phase 8: Observe It, Break It, Fix It (Observabilitas, Simulasi Insiden, Pemulihan & Teardown)

Dashboard pemantauan tidak akan berguna jika hanya menjadi pajangan. Pada fase terakhir ini, kita akan menggunakan *dashboard* Grafana dan aturan *alert* Prometheus terhadap layanan produksi secara *live*, sengaja memicu kegagalan nyata (*chaos/incident simulation*), mengamati bagaimana *alert* bereaksi, memulihkan layanan, menulis *Runbook*, dan terakhir menghancurkan infrastruktur agar tidak memakan biaya.

### Langkah 8.1 — Hasilkan Traffic Stabil ke Server Produksi
Ambil alamat IP publik server dari *output* Terraform, lalu jalankan perulangan `while true` untuk mengirimkan 5 *request* per detik (jeda `0.2` detik) ke server produksi. Sambil perulangan berjalan, amati pergerakan panel **Requests / s** dan **p95 latency** di Grafana (`http://IP_PUBLIK:3000`).

```bash
IP=$(cd infra && terraform output -raw public_ip)
while true; do curl -s "http://$IP/" > /dev/null; sleep 0.2; done
```

*(Tekan `Ctrl+C` untuk menghentikan pengirim trafik setelah Anda selesai mengamati grafik di Grafana).*

### Langkah 8.2 — Simulasikan Error 404 (Bukan Error Server 5xx)
Kirimkan 300 *request* ke alamat *path* yang tidak ada (`/missing`) sehingga server mengembalikan status **HTTP 404 Not Found**. Karena `404` adalah kesalahan dari sisi klien (*client error* `4xx`) dan **bukan** kegagalan internal server (`5xx`), panel **5xx ratio (5m)** di Grafana akan tetap berwarna **hijau (0%)**. Ini adalah pengingat penting dalam dunia SRE (*Site Reliability Engineering*): tidak semua respons non-200 layak membangunkan *engineer* di tengah malam!

```bash
for i in $(seq 1 300); do curl -s -o /dev/null "http://$IP/missing"; done
```

**Cara Cek (*Check*):** Buka antarmuka Prometheus di `http://IP_PUBLIK:9090`, jalankan kueri PromQL `sum by (status) (rate(http_requests_total[1m]))`. Anda akan melihat deret metrik untuk `status="404"` muncul, sementara rasio `5xx` tetap `0`.

### Langkah 8.3 — Simulasikan Outage Nyata (Matikan Kontainer Aplikasi)
Sekarang mari kita buat insiden sesungguhnya: hentikan kontainer `app` di server produksi menggunakan AWS SSM Run Command, lalu amati halaman **Prometheus → Alerts** (`http://IP_PUBLIK:9090/alerts`). Anda akan melihat aturan **`AppDown`** berubah status dari **Inactive (Hijau)** → **Pending (Kuning)** → hingga akhirnya **Firing (Merah)**!

```bash
aws ssm send-command --targets Key=tag:Name,Values=zero-to-prod --document-name AWS-RunShellScript \
  --parameters 'commands=["cd /opt/app && docker compose stop app"]' --query Command.CommandId --output text
```

**Cara Cek (*Check*):** Dalam waktu sekitar **90 detik** (15 detik interval *scrape* + 60 detik durasi `for: 1m` + siklus evaluasi), *alert* `AppDown` akan menyala merah (**Firing**) dan grafik laju *request* di Grafana jatuh ke angka nol.

### Langkah 8.4 — Pulihkan Layanan dan Konfirmasi Alert Kembali Normal
Nyalakan kembali kontainer `app` menggunakan SSM Run Command (persis seperti cara *pipeline* menyalakannya), lalu pastikan *alert* kembali tenang.

```bash
aws ssm send-command --targets Key=tag:Name,Values=zero-to-prod --document-name AWS-RunShellScript \
  --parameters 'commands=["cd /opt/app && docker compose up -d app"]' --query Command.CommandId --output text
```

**Cara Cek (*Check*):** Status `AppDown` di Prometheus kembali menjadi **Inactive (Hijau)** dan trafik di *dashboard* Grafana kembali normal.

### Langkah 8.5 — Dokumentasikan Runbook di `README.md`
Tuliskan apa yang baru saja Anda pelajari ke dalam file `README.md` di bawah subjudul **`## Runbook`**:
- Bagaimana cara memeriksa apakah aplikasi sedang menyala (`/health` dan SSM Run Command `docker ps`).
- Di mana letak *dashboard* Grafana (`:3000`) dan Prometheus (`:9090`).
- Bagaimana prosedur melakukan **Rollback** jika rilis terbaru bermasalah (jalankan ulang *job* `deploy` dengan *tag* `sha-…` lama, atau ubah `APP_IMAGE` di `/opt/app/.env` ke *tag* sebelumnya lalu jalankan `docker compose up -d app`).

Simpan dan gabungkan perubahan `README.md` tersebut melalui *Pull Request*. Dokumen *Runbook* inilah yang akan menyelamatkan Anda (atau rekan tim Anda) ketika terjadi insiden pada pukul 2 dini hari!

### Langkah 8.6 — Hancurkan Infrastruktur (`terraform destroy`) Agar Bebas Biaya
Setelah Anda selesai bereksperimen dan mengambil tangkapan layar (*screenshot*) untuk portofolio Anda, hancurkan infrastruktur EC2 dan Elastic IP menggunakan `terraform destroy` agar tidak terus memakan biaya di AWS. Bucket S3 *state* dan IAM Role dapat tetap dibiarkan karena keduanya **100% gratis** — sehingga kapan pun Anda ingin mendemonstrasikan proyek ini lagi (misalnya sebelum wawancara kerja), Anda cukup menjalankan satu perintah `terraform apply`!

```bash
cd infra
terraform destroy
```

**Cara Cek (*Check*):**
- Jalankan perintah verifikasi berikut:
  `aws ec2 describe-instances --filters Name=tag:Name,Values=zero-to-prod --query 'Reservations[].Instances[].State.Name'`
  dan pastikan hasilnya menampilkan `"terminated"`.
- Periksa konsol web EC2 untuk memastikan tidak ada *instance* yang masih berstatus *running* dan tidak ada *Elastic IP* yang tertinggal.

---

## Troubleshooting (Pemecahan Masalah Umum)

Berikut adalah daftar kendala yang paling sering ditemui beserta penyebab dan cara mengatasinya:

1. **`gh repo create` mengatakan nama repositori sudah ada (*already exists*)**
   - **Penyebab:** Anda sudah pernah membuat repositori dengan nama tersebut sebelumnya.
   - **Solusi:** Jalankan `gh repo clone zero-to-prod` untuk mengunduhnya, atau pilih nama lain dan gunakan nama tersebut secara konsisten di seluruh perintah berikutnya.

2. **`docker: permission denied` di Ubuntu Linux**
   - **Penyebab:** Anda sudah menambahkan *user* ke grup `docker` (`usermod -aG docker`), tetapi sesi terminal Anda saat ini belum memuat ulang keanggotaan grup tersebut.
   - **Solusi:** Jalankan `newgrp docker` untuk menerapkan grup baru pada *shell* saat ini, atau *log out* dan *log in* kembali ke Ubuntu.

3. **Workflow `release` gagal pada langkah `docker/login-action` dengan kode error `403 Forbidden`**
   - **Penyebab:** Meskipun `packages: write` sudah tertulis di YAML, pengaturan bawaan repositori GitHub mungkin membatasi izin penulisan `GITHUB_TOKEN`.
   - **Solusi:** Buka repositori di GitHub → **Settings → Actions → General → Workflow permissions** → pilih **Read and write permissions** lalu klik **Save**.

4. **Server berhasil mengunduh image, tetapi kontainer `app` langsung mati (*exits immediately*)**
   - **Penyebab & Diagnostik:** Jalankan perintah log melalui SSM Run Command: `cd /opt/app && docker compose logs app --tail 50`. Penyebab paling umum adalah paket di GHCR masih berstatus **Private** sehingga proses `pull` gagal.
   - **Solusi:** Ubah visibilitas paket GHCR menjadi **Public** (lihat Langkah 5.6).

5. **`terraform init` gagal dengan pesan `AccessDenied` pada S3 Bucket**
   - **Penyebab:** Nama *bucket* yang tertulis di `infra/backend.tf` tidak sama persis dengan nama *bucket* yang Anda buat, atau AWS CLI Anda terhubung ke akun AWS yang berbeda.
   - **Solusi:** Jalankan `aws s3 ls` untuk melihat nama *bucket* yang sebenarnya dan samakan dengan isi `infra/backend.tf`.

6. **Terraform melaporkan bahwa parameter AMI (`al2023`) tidak ditemukan**
   - **Penyebab:** Parameter SSM `/aws/service/ami-amazon-linux-latest/...` tersedia di setiap *region* AWS. Error ini biasanya terjadi karena *region* di AWS CLI dan nilai `var.region` di Terraform tidak sama.
   - **Solusi:** Pastikan *region* pada `backend.tf`, `variables.tf`, dan `aws configure` menggunakan *region* yang sama persis (misalnya `eu-west-1`).

7. **Grafana di port `3000` tidak bisa dibuka (timeout), padahal aplikasi di port `80` lancar**
   - **Penyebab:** Port `3000` dan `9090` di *Security Group* hanya dibuka untuk alamat IP publik Anda (`my_ip`). Jika Anda berpindah jaringan Wi-Fi, menyalakan VPN, atau ISP Anda merotasi IP publik, alamat IP Anda telah berubah.
   - **Solusi:** Perbarui nilai `my_ip` di `infra/terraform.tfvars` (atau variabel repositori `MY_IP` di GitHub) dengan hasil `$(curl -s https://checkip.amazonaws.com)/32` terbaru, lalu jalankan `terraform apply` kembali.

8. **`configure-aws-credentials` gagal dengan pesan `Not authorized to perform sts:AssumeRoleWithWebIdentity`**
   - **Penyebab:** Kondisi `sub` pada *trust policy* IAM Role tidak cocok persis dengan `repo:YOUR_USER/zero-to-prod:*` (termasuk perbedaan huruf besar/kecil pada *username* GitHub), atau *OIDC provider* belum terdaftar di akun AWS.
   - **Solusi:** Periksa *trust policy* yang terpasang saat ini dengan menjalankan `aws iam get-role --role-name github-zero-to-prod` dan perbaiki jika ada salah ketik.

9. **Komentar `Terraform plan` pada Pull Request kosong melompong**
   - **Penyebab:** Action `hashicorp/setup-terraform` membungkus (*wraps*) binary Terraform agar *output* `stdout` dapat ditangkap oleh ekspresi `${{ steps.plan.outputs.stdout }}`.
   - **Solusi:** Pastikan langkah `terraform plan` memiliki atribut `id: plan` dan Anda **tidak** mematikan pembungkusnya dengan `terraform_wrapper: false`.

10. **Job `deploy` berhasil (*Success*), tetapi versi aplikasi yang berjalan di server tidak berubah**
    - **Penyebab:** Periksa *output* SSM Run Command yang tercetak di *log* GitHub Actions. Jika perintah `sed` gagal memperbarui file `.env`, maka `docker compose up -d app` tidak akan melakukan apa-apa (*no-op*) karena referensi `APP_IMAGE=` tidak berubah.
    - **Solusi:** Pastikan baris `APP_IMAGE=` berada tepat di awal baris di dalam file `/opt/app/.env` pada server.

---

## Langkah Selanjutnya (*Where to Go from Here*)

Setelah menyelesaikan seluruh 8 fase di atas, Anda dapat mengembangkan arsitektur proyek ini lebih jauh sebagai nilai tambah portofolio:

1. **Ganti EC2 Tunggal dengan Platform Terkelola (AWS ECS + ALB)**: Pindahkan kontainer yang sama ke klaster **Amazon ECS (Fargate)** di belakang *Application Load Balancer* (ALB) dengan arsitektur VPC multi-AZ (*Public & Private Subnets*).
2. **Tambahkan Lingkungan Staging (*Staging Environment*)**: Buat *workspace* Terraform kedua dan atur agar *workflow* `release` men-*deploy* ke *Staging* terlebih dahulu, lalu membutuhkan persetujuan manual (*manual approval* melalui fitur **GitHub Environments**) sebelum lanjut men-*deploy* ke *Production*.
3. **Terapkan SLI, SLO, dan Burn-Rate Alerts (SRE Track)**: Ubah panel rasio *error* dan latensi menjadi *Service Level Indicator* (SLI) dan *Service Level Objective* (SLO) formal lengkap dengan peringatan laju pembakaran *error budget* (*burn-rate alerts*).
4. **Perkuat Keamanan (*Cybersecurity / DevSecOps Track*)**: Tambahkan pemindaian celah keamanan *image* (misalnya dengan **Trivy**) di dalam pipeline CI, tanda tangani *container image* secara kriptografis menggunakan **Sigstore Cosign**, dan persempit izin IAM Role `github-zero-to-prod` agar hanya memuat aksi-aksi spesifik (*least privilege*) tanpa kebijakan `FullAccess`.
5. **Kunci Tag `sha-` di Variabel Terraform**: Ganti penggunaan *tag* `:latest` pada variabel `image` Terraform dengan *tag* `sha-…` spesifik agar jika server EC2 dibangun ulang dari awal (*rebuilt*), ia selalu langsung menjalankan versi *image* terakhir yang teruji di produksi.
