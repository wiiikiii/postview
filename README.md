# Postview

A self-hosted PostgreSQL database browser built with Rails 8 and Tailwind CSS.

![Ruby](https://img.shields.io/badge/Ruby-3.4-red) ![Rails](https://img.shields.io/badge/Rails-8.1-red) ![Tailwind](https://img.shields.io/badge/Tailwind-4.x-blue)

## What it does

Postview connects directly to your PostgreSQL server using HTTP Basic Auth and lets you browse:

- All databases on the server
- All tables within a database
- Paginated row data for any table (25 rows per page)

No separate user management — login credentials are your actual PostgreSQL credentials.

## Requirements

- Ruby 3.1+
- PostgreSQL 14+
- Bundler

## Setup

```bash
bundle install
bin/rails db:create
```

## Running

```bash
bin/dev
```

Opens at `http://localhost:3000`. Login with your PostgreSQL username and password.

For a custom port:

```bash
bin/rails server -p 3100
```

## Stack

| Layer       | Technology              |
|-------------|-------------------------|
| Framework   | Rails 8.1               |
| Database    | PostgreSQL              |
| CSS         | Tailwind CSS 4          |
| JavaScript  | Importmap + Turbo       |
| Assets      | Propshaft               |
| Pagination  | Kaminari                |
| Web server  | Puma                    |

## Architecture note

Postview has no schema of its own beyond the Rails boot database. It introspects the target PostgreSQL server at runtime and creates ActiveRecord model classes dynamically — one module per database, one class per table — allowing it to browse any database without prior configuration.

```
Database::Mydb::Connect   →  connection to "mydb"
Database::Mydb::Users     →  AR model for the "users" table in "mydb"
Database::Mydb::Orders    →  AR model for the "orders" table in "mydb"
```

See [TECHNICAL.md](TECHNICAL.md) for the full technical documentation.

## Production

Set the database password via environment variable and precompile assets:

```bash
RAILS_ENV=production POSTVIEW8_DATABASE_PASSWORD=secret bin/rails db:create
RAILS_ENV=production bin/rails assets:precompile
RAILS_ENV=production bin/rails server
```

Docker deployment is pre-configured via [Kamal](https://kamal-deploy.org) — see `config/deploy.yml`.

## Security

- Authentication is delegated entirely to PostgreSQL — no credentials are stored by the app
- There are no write endpoints; all queries are read-only by default
- Recommended for localhost or internal network use only
