# SupaNotes

Personal notes app with proactive AI capabilities.

## Prerequisites

- Docker & Docker Compose
- Go 1.22+
- Flutter 3.44+
- PostgreSQL 16 (via Docker)

## Setup

### 1. Clone and enter the repo

```bash
git clone https://github.com/RigleyC/supanotes
cd supanotes
```

### 2. Start the database

```bash
docker compose up -d
```

### 3. Configure environment

```bash
cp backend/.env.example backend/.env
```

Edit `backend/.env` with your API keys.

### 4. Run database migrations

```bash
make -C backend migrate-up
```

### 5. Start the backend

```bash
make -C backend run
```

### 6. Run the Flutter app

```bash
flutter run
```
