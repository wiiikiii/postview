# Postview8 — Technical Documentation

## Overview

Postview8 is a self-hosted PostgreSQL database browser. It connects directly to the PostgreSQL server via HTTP Basic Auth and displays databases, tables, and their contents — without maintaining any data tables of its own. The app is a rewrite of Postview (Rails 4.2) targeting Rails 8.

---

## Technology Stack

| Component      | Technology                       | Version  |
|----------------|----------------------------------|----------|
| Framework      | Ruby on Rails                    | 8.1.3    |
| Language       | Ruby                             | 3.4+     |
| Database       | PostgreSQL (target + app own DB) | 14+      |
| Asset Pipeline | Propshaft                        | —        |
| CSS            | Tailwind CSS                     | 4.x      |
| JavaScript     | Importmap + Turbo + Stimulus     | —        |
| Pagination     | Kaminari                         | 5.3      |
| Web Server     | Puma                             | 8.x      |

---

## Project Structure

```
postview8/
├── app/
│   ├── controllers/
│   │   ├── application_controller.rb   # HTTP Basic Auth against PostgreSQL
│   │   └── main_controller.rb          # Three actions: index, database, table
│   ├── models/
│   │   └── database.rb                 # Dynamic AR models created at runtime
│   └── views/
│       ├── layouts/application.html.erb
│       └── main/
│           ├── index.html.erb          # Database list
│           ├── database.html.erb       # Table list
│           └── table.html.erb          # Table rows with pagination
├── config/
│   ├── routes.rb
│   └── database.yml
└── TECHNICAL.md
```

---

## Routes

```
GET /                          → main#index     (database list)
GET /databases/:id             → main#database  (tables in a database)
GET /databases/:db/:table      → main#table     (rows in a table)
GET /up                        → health check
```

Named helpers:
- `root_path` → `/`
- `database_path("mydb")` → `/databases/mydb`
- `database_table_path("mydb", "users")` → `/databases/mydb/users`

---

## Authentication

**File:** [app/controllers/application_controller.rb](app/controllers/application_controller.rb)

The app uses **HTTP Basic Auth**, where the submitted credentials are used directly as the PostgreSQL login. There is no application-level user table.

### Per-request flow

```
Browser sends: Authorization: Basic base64(user:password)
                    │
                    ▼
    authenticate_or_request_with_http_basic
                    │
                    ▼
    ActiveRecord::Base.establish_connection(
      config.merge(username: user, password: password)
    )
                    │
                    ▼
    execute("SELECT 1")  ← tests the connection
                    │
           ┌────────┴────────┐
        success          failure (PG::Error)
           │                 │
     @current_user = user   false → 401 returned
```

**Note:** `establish_connection` replaces the global AR connection for the duration of the request. The app is suitable for single-user use; multi-user operation would require request-scoped connection pooling.

---

## Dynamic ActiveRecord Models

**File:** [app/models/database.rb](app/models/database.rb)

This is the most technically interesting part of the app. Because the databases and tables to be displayed are unknown at compile time, ActiveRecord classes are created **at runtime**.

### Class structure after the first access to "mydb"

```
Database                        (AR class → pg_database, default connection)
└── Database::Mydb              (module, namespace for a single database)
    ├── Database::Mydb::Connect (AR class → pg_database, connected to "mydb")
    ├── Database::Mydb::Users   (AR class → users table in "mydb")
    ├── Database::Mydb::Orders  (AR class → orders table in "mydb")
    └── ...
```

### `tables_for(database_name)` — flow

```ruby
Database.tables_for("mydb")
```

1. **`ensure_namespace("mydb")`** — checks whether `Database::Mydb` exists:
   - No → creates the module and registers it as `Database::Mydb`
   - Creates `Database::Mydb::Connect < ActiveRecord::Base`
   - Sets the constant **before** any AR config (required in Rails 8 — no anonymous classes)
   - Calls `establish_connection(config.merge(database: "mydb"))`

2. **Cache check** — if `@table_names` is already set, returns immediately (avoids repeated DB queries)

3. **Load tables** — `db_module::Connect.connection.tables.sort`:
   - For each table: `object_classify_name(table)` → e.g. `"user_roles"` → `"UserRole"`
   - Creates `Class.new(db_module::Connect)`
   - Sets the constant **before** any AR configuration (Rails 8 requirement)
   - Sets `table_name` and `primary_key = nil`

4. Returns a sorted array of original table name strings

### `model_for(database_name, table_name)` — lookup

```ruby
Database.model_for("mydb", "user_roles")
# => Database::Mydb::UserRole
```

### Name mapping: `object_classify_name`

```ruby
"user_roles"        → "UserRole"
"my-table"          → "MyTable"
"schema.table"      → "SchemaTable"
"api_auth_tokens"   → "ApiAuthToken"
```

Rules: `-` and `.` are replaced with `_`, then Rails `classify` is applied (singularize + CamelCase).

### Rails 8-specific constraints

| Problem | Cause | Solution |
|---------|-------|----------|
| `raise "Anonymous class is not allowed"` | `establish_connection` called on an unnamed class | call `const_set` **before** `establish_connection` |
| False-positive `const_defined?` | Default lookup traverses the namespace hierarchy | use `const_defined?(name, false)` — direct constants only |
| `"pool" and "max_connections" conflict"` | Rails 8 uses `max_connections` instead of `pool` in database.yml | do not include `pool:` in the connection config hash |

---

## Controller

**File:** [app/controllers/main_controller.rb](app/controllers/main_controller.rb)

### `index`
Reads `pg_database` via the standard AR adapter (switched to user credentials by auth). Returns all visible databases sorted by name.

### `database`
Calls `Database.tables_for(params[:id])` and passes the table list to the view. On first access, this builds the entire class hierarchy for the given database.

### `table`
Resolves the AR class for the given database and table, reads columns via `column_names`, and paginates rows with Kaminari (25 per page). `NameError` for unknown tables is rescued and returned as a redirect with a flash message.

---

## Views & UI

All views use **Tailwind CSS 4** without any external component library.

### Design principles
- Dark navigation bar (`bg-slate-800`) with a breadcrumb trail
- Content area in `bg-gray-100` with white cards (`bg-white rounded-xl border`)
- Consistent card grids for databases and tables (responsive, 2–6 columns)
- Table data: `font-mono text-xs`, NULL values visually distinguished, long strings truncated

### Pagination (table.html.erb)
Kaminari is used for the data query (`model.page(p).per(25)`); the pagination controls are built manually in Tailwind (no kaminari view generator needed).

---

## Database Connections

The app manages **multiple concurrent connections**:

| Connection  | Class                       | Target                                      |
|-------------|-----------------------------|--------------------------------------------|
| Base        | `ActiveRecord::Base`        | `postview8_development` (Rails boot DB)    |
| Auth        | overrides `ActiveRecord::Base` | user credentials on the base DB         |
| Per target DB | `Database::DbName::Connect` | separate database on the same server    |

Each `Connect` class has its own connection pool managed by `establish_connection`. The pool persists for the lifetime of the process.

---

## Setup

### Prerequisites
- Ruby 3.1+
- PostgreSQL 14+ (locally reachable)
- Bundler

### Installation

```bash
git clone <repo>
cd postview8
bundle install
bin/rails db:create
```

### Start development server

```bash
bin/dev          # starts Puma + Tailwind watcher
```

Then open `http://localhost:3000` in your browser.

Login with your local PostgreSQL username and password.

### Production

```bash
RAILS_ENV=production POSTVIEW8_DATABASE_PASSWORD=xxx bin/rails db:create
RAILS_ENV=production bin/rails assets:precompile
RAILS_ENV=production bin/rails server
```

Or via Kamal (Docker deployment, configured in `config/deploy.yml`).

---

## Security Considerations

### What the app protects
- Every request requires valid PostgreSQL credentials
- Invalid credentials → immediate 401, no session created
- `NameError` on unknown table references → redirect, no stack trace exposed

### Known limitations
- **Single-user:** `establish_connection` changes the global connection; parallel requests from different users can interfere with each other
- **Read-only by design:** No write endpoints exist, but there is no technically enforced read-only mode at the database level
- **Localhost recommended:** The app exposes all databases the authenticated PostgreSQL user has access to

### Not implemented (compared to enterprise tools)
- Row-level security
- Column blacklisting
- Audit log
- Query limits / timeouts

---

## Differences from the Original (Rails 4.2)

| Aspect | Postview (old) | Postview8 (new) |
|--------|---------------|-----------------|
| `connection.instance_eval { @config }` | ✓ (private API) | `connection_db_config.configuration_hash` |
| `render :text` | ✓ (removed in Rails 5) | `render plain:` |
| `attributes_protected_by_default` | ✓ (removed in Rails 5) | removed |
| Anonymous AR classes | ✓ | `const_set` before `establish_connection` |
| `const_defined?` without `false` | ✓ (namespace lookup bug) | `const_defined?(name, false)` |
| Bootstrap 3 + CoffeeScript | ✓ | Tailwind 4 + Importmap |
