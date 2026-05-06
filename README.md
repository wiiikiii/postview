# Postview

A self-hosted PostgreSQL database browser built with Rails 8 and Tailwind CSS.

![Ruby](https://img.shields.io/badge/Ruby-3.4-red) ![Rails](https://img.shields.io/badge/Rails-8.1-red) ![Tailwind](https://img.shields.io/badge/Tailwind-4.x-blue)

## What it does

Postview connects to your PostgreSQL server and lets you browse:

- All databases on the server with statistics (size, cache hit rate, ACL, schemas, ...)
- All tables within a database
- Paginated, searchable row data with per-column filtering
- Table structure (columns, types, constraints, indexes)

Login via username/password, Magic Link, or with two-factor authentication (TOTP).
A REST API with bearer token auth provides programmatic access to all data.

## Requirements

- Ruby 3.1+
- PostgreSQL 14+
- Bundler

## Setup

### 1. Credentials & master key

Rails encrypts secrets in `config/credentials.yml.enc` using `config/master.key`.
Neither file is committed to version control. Restore or create them:

**If you have an existing `master.key` and `credentials.yml.enc`** (e.g. from a backup):
```bash
# Place both files at their expected paths:
config/master.key
config/credentials.yml.enc
```

**If you are setting up from scratch**, generate a fresh pair:
```bash
bin/rails credentials:edit
# This creates config/master.key and config/credentials.yml.enc
# Add your secrets (e.g. secret_key_base) and save.
```

> `config/master.key` must never be committed to git — it is already in `.gitignore`.
> Without it, the app cannot start in production and credentials cannot be decrypted.

### 2. Install dependencies & prepare the database

```bash
bundle install
bin/rails db:create
bin/rails db:migrate
bin/rails db:seed        # creates the default admin user
```

The seed creates an initial user:

| Field         | Default value       |
|---------------|---------------------|
| Username      | `admin`             |
| Password      | `changeme`          |
| PG user       | `postgres`          |
| PG password   | `postgres`          |

Change the password after first login via the profile page.

## Running

```bash
bin/dev
```

Opens at `http://localhost:3000`. Log in with the admin credentials above.

For a custom port:

```bash
bin/rails server -p 3100
```

## Authentication

| Method       | Description                                              |
|--------------|----------------------------------------------------------|
| Password     | Username + password login                                |
| Magic Link   | Passwordless login via a one-time link (15 min expiry)   |
| 2FA (TOTP)   | Optional second factor via any TOTP app (Authy, etc.)    |

### Magic Link in development

Magic links are printed directly into the flash notice (no SMTP required in development).
In production, configure `config/environments/production.rb` with your SMTP settings and
uncomment the mailer delivery in `app/controllers/magic_links_controller.rb`.

## API

The REST API is available at `/api/v1/`. All endpoints require a Bearer token:

```
Authorization: Bearer <your-token>
```

Tokens are created on the profile page (`/profile`). Interactive documentation is at `/api/docs`.

### Endpoints

| Method | Path                                          | Description             |
|--------|-----------------------------------------------|-------------------------|
| GET    | `/api/v1/databases`                           | List databases          |
| GET    | `/api/v1/databases/:db/tables`                | List tables             |
| GET    | `/api/v1/databases/:db/tables/:table/rows`    | Paginated row data      |
| GET    | `/api/v1/databases/:db/tables/:table/structure` | Column + index info   |

Query parameters for rows: `q` (search), `page`, `per_page` (max 100).

## Stack

| Layer         | Technology                     |
|---------------|--------------------------------|
| Framework     | Rails 8.1                      |
| Database      | PostgreSQL                     |
| CSS           | Tailwind CSS 4                 |
| JavaScript    | Importmap + Turbo + Stimulus   |
| Assets        | Propshaft                      |
| Pagination    | Kaminari                       |
| 2FA           | ROTP + RQRCode                 |
| Web server    | Puma                           |

## Architecture note

Postview has a minimal schema (users, api_tokens, magic_links). For browsed databases it
introspects the target PostgreSQL server at runtime and creates ActiveRecord model classes
dynamically — one module per database, one class per table:

```
Database::Mydb::Connect   →  connection pool for "mydb"
Database::Mydb::Users     →  AR model for the "users" table in "mydb"
Database::Mydb::Orders    →  AR model for the "orders" table in "mydb"
```

Each dynamic connection uses `pool: 3, idle_timeout: 60` to limit total connections.

## Production

```bash
RAILS_ENV=production bin/rails assets:precompile
RAILS_ENV=production bin/rails db:migrate
RAILS_ENV=production bin/rails server
```

Set the app database credentials in `config/credentials.yml.enc` (via `bin/rails credentials:edit`).

Docker deployment is pre-configured via [Kamal](https://kamal-deploy.org) — see `config/deploy.yml`.

## Security

- PostgreSQL credentials are stored per user in the `users` table (plaintext — enable disk encryption or use a secrets manager in production)
- API tokens are stored as SHA-256 digests; the raw token is shown only once at creation
- 2FA secrets are stored in the `users` table (otp_secret); consider database encryption for production
- All write endpoints are absent — Postview is a read-only browser
- Recommended for localhost or internal network use only
