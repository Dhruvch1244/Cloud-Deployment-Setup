# EC2 -> RDS PostgreSQL Setup

Run everything below on the EC2 instance.

## Environment
- RDS endpoint: `database-test.c9s8s8keichb.ap-south-1.rds.amazonaws.com`
- Port: `5432`
- DB name: `postgres`
- Master user: `postgres`

---

## Step 1: Clone the GitHub repo (using a PAT)

Replace `<github-username>`, `<PAT>`, `<owner>` and `<repo>` with your own values.

```bash
git clone https://<github-username>:<PAT>@github.com/<owner>/<repo>.git
cd <repo>
```

---

## Step 2: Install the Postgres client

```bash
# Ubuntu / Debian
sudo apt update
sudo apt install -y postgresql-client
```

Verify:

```bash
psql --version
```

---

## Step 3: Test the connection

Set the connection variables once:

```bash
export PGHOST=database-test.c9s8s8keichb.ap-south-1.rds.amazonaws.com
export PGPORT=5432
export PGUSER=postgres
export PGDATABASE=postgres
export PGSSLMODE=require
export PGPASSWORD='<your-password>'
```

Network check:

```bash
timeout 5 bash -c '</dev/tcp/database-test.c9s8s8keichb.ap-south-1.rds.amazonaws.com/5432' && echo "OPEN" || echo "BLOCKED/TIMEOUT"
```

Server check:

```bash
pg_isready -h $PGHOST -p $PGPORT
```

Login check:

```bash
psql -c "SELECT version();"
psql -c "SELECT current_database(), current_user, now();"
```

---

## Step 4: Load schema and seed data

Run the migration files in order:

```bash
cd /path/to/migrations
for f in $(ls *.sql | sort -V); do
  echo "Running $f"
  psql -v ON_ERROR_STOP=1 -f "$f" || { echo "FAILED on $f"; break; }
done
psql -c "\dt"
```

**Does the connection stay open on the RDS after these commands?**
No. Each `psql` command opens its own connection, runs, and closes it when it finishes. The tables and data stay in the database permanently, but the connections do not.

---

## Step 5: Sample SELECT queries to check the tables

```bash
psql -c "\dt"
psql -c "\d <table-name>"
psql -c "SELECT count(*) FROM <table-name>;"
psql -c "SELECT * FROM <table-name> LIMIT 10;"
```
