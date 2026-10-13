# Docker template: frontend + Node API + Java API + Java worker

A reusable Docker Compose setup for applications shaped like the capstone trading platform:
a single-page frontend, a Node service, one or two Spring Boot services,
Postgres, Kafka and a mail catcher, all on one machine.

**You edit one file: `.env`.** The Dockerfiles are never edited, and
`docker-compose.yml` is edited only in the cases listed under
[When the compose file itself must change](#when-the-compose-file-itself-must-change).

## What is in this folder

| File | What it is | Do you edit it? |
|---|---|---|
| `.env.example` | Every setting, grouped by how likely it is to change | Copy to `.env`, then **yes** |
| `docker-compose.yml` | The stack; reads everything from `.env` | Rarely (lines tagged `<<CHANGE>>`) |
| `dockerfiles/node.Dockerfile` | Any npm service | No |
| `dockerfiles/java.Dockerfile` | Any Maven / Gradle-wrapper service | No |
| `dockerfiles/frontend.Dockerfile` | Angular / React / Vue on nginx | No |
| `dockerfiles/dockerignore.sample` | Keeps secrets and build output out of images | No |
| `nginx/default.conf.template` | Frontend proxy, filled from `.env` at start | No |
| `check.sh` | Pre-flight check; reports what would fail | No |
| `mock/fauxnance-mock.js` | Stand-in for the market-data API, for testing trades without a key | No |
| `empty/` | Empty folder used as a default mount | No |

## Setup

Run everything from the root of your application's repository. Do this on a
branch, not on `main`.

### Step A. Get this folder into your repository

```bash
git clone https://github.com/IM-RAHUL-RAJ/Cloud-Deployment-Setup /tmp/cloud-setup
cp -r /tmp/cloud-setup/docker-template ./docker-template
```

The `docker-template/` folder must stay in the repository root, because the
compose file mounts files from it.

### Step B. Rename your existing Docker files (do not delete them)

Your own Dockerfiles and compose files are kept as `*.999`, so you can compare
or go back at any time. This renames every `Dockerfile*`, `.dockerignore` and
`*compose*.yml` in the repository except the ones inside `docker-template/`:

```bash
# 1. look first: this only LISTS what would be renamed
find . \( -name node_modules -o -name .git -o -name docker-template -o -name target -o -name dist \) -prune -o \
  -type f \( -iname 'Dockerfile*' -o -name '.dockerignore' -o -iname '*compose*.yml' -o -iname '*compose*.yaml' \) \
  ! -name '*.999' -print

# 2. rename them
find . \( -name node_modules -o -name .git -o -name docker-template -o -name target -o -name dist \) -prune -o \
  -type f \( -iname 'Dockerfile*' -o -name '.dockerignore' -o -iname '*compose*.yml' -o -iname '*compose*.yaml' \) \
  ! -name '*.999' -exec mv -n {} {}.999 \;
```

To go back later: delete the generic file and remove the `.999` suffix from
yours (`mv Dockerfile.999 Dockerfile`).

### Step C. Copy the generic files into place

Replace the `<...>` parts with your own folder names (spelled exactly as on
disk; Linux is case-sensitive).

```bash
cp docker-template/docker-compose.yml .
cp docker-template/.env.example .env

cp docker-template/dockerfiles/node.Dockerfile      <auth-service-folder>/Dockerfile
cp docker-template/dockerfiles/java.Dockerfile      <order-service-folder>/Dockerfile
cp docker-template/dockerfiles/java.Dockerfile      <executor-service-folder>/Dockerfile
cp docker-template/dockerfiles/frontend.Dockerfile  <frontend-folder>/Dockerfile

# the same ignore file into each of those four folders
for d in <auth-service-folder> <order-service-folder> <executor-service-folder> <frontend-folder>; do
  cp docker-template/dockerfiles/dockerignore.sample "$d/.dockerignore"
done
```

Do not edit the copied Dockerfiles or `docker-compose.yml`. Everything is set
in `.env`.

### Step D. Keep secrets out of git

```bash
grep -qxF '.env' .gitignore || echo '.env' >> .gitignore
git status --short        # .env must NOT be listed
```

### Step E. Fill in `.env`, then start

Work through the checklist below, then:

```bash
./docker-template/check.sh
docker compose up --build -d
docker compose ps
```

## Checklist

Work through this top to bottom. Each step names the `.env` keys it sets and
how to find the right value in the application's code.

### 1. Machine

- [ ] Docker is running, Compose is 2.24 or newer, buildx is 0.17 or newer.
      `./docker-template/check.sh` reports all three.
- [ ] The browser-facing ports are open in the firewall or Security Group:
      only the frontend port.

### 2. What runs

- [ ] `COMPOSE_PROJECT_NAME`: a short lowercase name.
- [ ] `COMPOSE_PROFILES`: remove the parts this application does not have.
      App parts are `frontend`, `node-api`, `java-api`, `java-worker`;
      infrastructure parts are `localdb`, `kafka`, `mail`, `kafka-ui`.
- [ ] `PUBLIC_HOST`: the address typed in the browser (server IP or DNS name).

### 3. Each service

For every service that is switched on:

- [ ] `*_DIR`: the folder, spelled exactly as on disk. Linux is case-sensitive,
      so `./Services` and `./services` are different folders.
- [ ] `*_PORT`: the port it should listen on.
- [ ] Language version: `NODE_API_NODE_VERSION`, `FRONTEND_NODE_VERSION`,
      `JAVA_*_JAVA_VERSION` (the last must equal `<java.version>` in `pom.xml`).
- [ ] `NODE_API_START_CMD`: copy it from `"start:prod"` in `package.json`.
      NestJS projects often build to `dist/src/main.js`, not `dist/main.js`.
- [ ] `*_HEALTH_PATH`: a URL that returns 200 **without logging in**.
      Spring Boot with actuator: `/actuator/health`. Leave it empty for a
      service with no HTTP endpoint; the check then only tests that the port is open.
- [ ] Java only: check for the three special layouts. Each is handled from
      `.env`; the top of `java.Dockerfile` shows the keys.
      - `pom.xml` depends on a **library that lives in the repo** (a `<dependency>`
        on something like `domain-engine`): use `JAVA_*_DIR` = the folder holding
        both, `JAVA_*_PRE_INSTALL_DIRS`, `JAVA_*_APP_DIR`, `JAVA_*_DOCKERFILE`.
      - An **aggregator pom** lists the services as `<modules>`: use
        `JAVA_*_DIR` = its folder and `JAVA_*_MODULE`.
      - `pom.xml` reads a **folder outside** the service (search for
        `<directory>../`): use `JAVA_*_EXTRA_DIR` and `JAVA_*_EXTRA_DEST`.
- [ ] Java only: does the service start another program (Python)? Set
      `JAVA_*_RUNTIME_APK=python3`. Scripts and pip packages it needs are not
      added; that case needs help.
- [ ] Shared config folder: do services read a file such as
      `Config/application.yml` at run time (look for `spring.config.import` or a
      `../../Config` path)? Set `APP_CONFIG_DIR` and `APP_CONFIG_MOUNT`.

### 4. Variable names the code reads

This is the step most likely to go wrong, because a missing or misnamed
variable usually produces a running container that does not work.

- [ ] List the names each service reads:

  ```bash
  # Node
  grep -rhoE "process\.env\.[A-Z_0-9]+|get(Optional)?\('[A-Z_0-9]+'" <dir>/src | sort -u
  # Java
  grep -rhoE '\$\{[A-Z_0-9]+' <dir>/src/main | sort -u
  ```

- [ ] Cross off the ones the template already provides (listed at the top of
      section 3 in `.env`): database, Kafka, CORS and port names.
- [ ] Add every remaining name to section 3 of `.env`.
- [ ] Any value that is the address of another service uses the **service
      name**, never `localhost`: `http://java-api:8081`, `kafka:29092`,
      `postgres:5432`, `mailpit:1025`.
- [ ] `JWT_SECRET` is the same value for the service that issues tokens and the
      ones that verify them, and so is the issuer name if the code checks one.

### 5. How the frontend reaches the backend

The browser talks only to the frontend port. The frontend's nginx forwards API
calls to the backends, so no API port has to be opened and no CORS setting is
needed. Find the API base address in the frontend's environment or config file,
then pick the matching case.

- [ ] **Case 1, absolute addresses** (`http://localhost:3000`, `http://localhost:8081`).
      No code change: list each address in `FRONTEND_URL_REWRITES` as `from=to`.
      On every container start, `from` is replaced in the built page by `to`.
      Use `.../_node` for the Node API and `.../_java` for the Java API:

      ```
      FRONTEND_URL_REWRITES=http://localhost:3000=${PUBLIC_SCHEME}://${PUBLIC_HOST}:${FRONTEND_PORT}/_node http://localhost:8081=${PUBLIC_SCHEME}://${PUBLIC_HOST}:${FRONTEND_PORT}/_java
      ```

      After the first start, `docker compose logs frontend | grep frontend:`
      shows how many files each pair changed. `0 file(s)` means that address is
      not in the page: check the spelling and port.
- [ ] **Case 2, relative addresses** (base is `''` or `/api`). List the first
      path segments in `FRONTEND_PROXY_KEEP_PATHS` (go to the Java API) and
      `FRONTEND_PROXY_KEEP2_PATHS` (go to the Node API), separated by `|`.
      A prefix that must be removed before forwarding goes in
      `FRONTEND_PROXY_NODE_PREFIX` or `FRONTEND_PROXY_JAVA_PREFIX`.
      A path used both as a page route and as an API path cannot be separated
      this way; that case needs help.
- [ ] The build runs a script first (`prebuild`, `sync-config`, `generate-env`):
      if it needs env values, set `FRONTEND_BUILD_ENV`; if it reads a file
      outside the frontend folder, set `FRONTEND_EXTRA_DIR` / `FRONTEND_EXTRA_DEST`.
- [ ] `PUBLIC_HOST` is exactly what is typed in the browser. If you reach the
      server through a tunnel as `localhost`, set `PUBLIC_HOST=localhost`.

### 6. Database

The connection is set once: `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`,
`DB_PASSWORD`. Every common variable name is derived from these.

- [ ] **RDS (the usual case):** `DB_HOST` = the RDS endpoint, and `localdb` is
      not in `COMPOSE_PROFILES`. The server's security group must be allowed in
      the RDS security group on port 5432.
- [ ] **Bundled Postgres:** add `localdb` to `COMPOSE_PROFILES` and set
      `DB_HOST=postgres`. Tables come from the application's own migration, or
      from SQL files in `DB_INIT_DIR` (run once, on an empty volume).
- [ ] Names in section 3 that carry the connection again (`DATABASE_URL`,
      `AUTH_DB_NAME` ...) reference the values above, e.g. `${DB_HOST}`, so
      nothing is typed twice.
- [ ] Non-default schema or TLS: `JDBC_PARAMS` (`?currentSchema=trading`,
      `?sslmode=require`).

### 7. Kafka

- [ ] `KAFKA_TOPICS` lists every topic the code produces to or consumes from,
      including dead-letter topics, as `name:partitions:retention_ms`.
      Topics are not auto-created, so a missing name fails at run time.
- [ ] No Kafka in this application: remove `kafka` from `COMPOSE_PROFILES`.

### 8. Start-up order

- [ ] Does any service need another one to finish first, typically the one that
      migrates the database? The template already makes `java-worker` wait for
      `java-api`. Anything else is a `<<CHANGE>>` edit in the compose file.

### 9. Build and start

```bash
./docker-template/check.sh          # fix every FAIL line
docker compose up --build -d
docker compose ps                   # every service healthy
```

### 10. Prove it works

Healthy containers are not proof. Test the path a user takes:

```bash
H=http://localhost:<FRONTEND_PORT>
curl -s -o /dev/null -w '%{http_code}\n' $H/                      # 200, the page
curl -s -o /dev/null -w '%{http_code} %{content_type}\n' $H/api/<any-endpoint>
```

- [ ] The API call returns JSON (a 401 is fine without a login). If it returns
      `text/html`, the proxy route is wrong: go back to step 5.
- [ ] Open the page, press F12, Network tab, and log in. Every API call must go
      to the frontend's own address. A call to `localhost:3000` or similar means
      an address is missing from `FRONTEND_URL_REWRITES`.
- [ ] Log in through the UI, or with curl, and call one protected endpoint.
      A 401 after a successful login means the `JWT_SECRET` or issuer differs
      between services (step 4).
- [ ] Do one end-to-end action (place an order, send a message) and confirm the
      worker's log shows it: `docker compose logs java-worker | tail`.
- [ ] `docker compose logs <service> | grep -iE "error|refused|unknown host"`
      is empty or explained.

## Optional parts and tools

All of these are switched on from `.env`; none needs a compose edit.

| Need | How |
|---|---|
| Bundled Postgres instead of RDS | Add `localdb` to `COMPOSE_PROFILES`, set `DB_HOST=postgres`. It accepts SSL and plain connections, like RDS. |
| Load schema and seed data into a fresh database | Set `DB_SEED_DIR` and `DB_SEED_COMMAND` (the team's own script), then `docker compose --profile seed run --rm db-seed`. Never run it against a database that already holds your data. |
| Test trades without a market-data key or quota | Add `mock-market` to `COMPOSE_PROFILES` and point the Fauxnance base URL at `http://market-mock:8089/v1`. Same paths and response shapes as the real API, made-up prices. `MOCK_MARKET_STATE=closed` tests the market-closed case. |
| Redis | Add `redis` to `COMPOSE_PROFILES`; the address is `redis://redis:6379`. |
| Catch outgoing mail | Profile `mail`; SMTP host `mailpit`, port `1025`; inbox at `http://localhost:8025` on the server. |
| Java app loads a native (glibc) library | `JAVA_*_RUNTIME_IMAGE=eclipse-temurin:21-jre-jammy` |
| Java app starts Python | `JAVA_*_RUNTIME_APK=python3` |
| Worker with no web server at all | `JAVA_WORKER_HEALTH_PATH=process` |
| Frontend build needs Java (OpenAPI generator) | `FRONTEND_BUILD_APK=openjdk17-jre-headless` |
| Frontend build needs a step first | `FRONTEND_PRE_BUILD_CMD='cd /config && npm install'` |
| Frontend build needs other arguments | `FRONTEND_BUILD_SCRIPT=ng`, `FRONTEND_BUILD_ARGS=build my-app` |
| Frontend build script reads env values | `FRONTEND_BUILD_ENV=NAME=value NAME2=value2` |

Handled automatically, with nothing to set: native Node modules that need a
compiler, a Spring Boot jar whose pom does not repackage, an application that
writes to `./logs`, a frontend build that insists on a `.env` file, and
interactive prompts of the Angular CLI.

## Commands you will use

Run them from the repository root, where `docker-compose.yml` and `.env` are.

| Task | Command |
|---|---|
| Check the machine and `.env` before starting | `./docker-template/check.sh` |
| Build everything and start | `docker compose up --build -d` |
| See what is running and whether it is healthy | `docker compose ps` |
| Follow the log of one service | `docker compose logs -f java-api` |
| Last 100 lines of every service | `docker compose logs --tail 100` |
| Find errors quickly | `docker compose logs node-api java-api java-worker \| grep -iE "error\|refused\|unknown host" \| tail` |
| Restart one service after changing `.env` | `docker compose up -d java-api` |
| Rebuild one service after changing its code | `docker compose up -d --build frontend` |
| Rebuild from scratch, ignoring the cache | `docker compose build --no-cache java-api` |
| Stop everything, keep the data | `docker compose down` |
| Stop everything and DELETE the bundled database and Kafka data | `docker compose down -v` |
| Open a shell inside a service | `docker compose exec node-api sh` |
| See the environment a service really received | `docker compose exec java-api env \| sort` |
| See the final compose file with `.env` filled in | `docker compose config` |
| Which addresses the frontend rewrote at start | `docker compose logs frontend \| grep "frontend:"` |
| Load schema and seed data into a fresh database | `docker compose --profile seed run --rm db-seed` |
| SQL prompt on the bundled database | `docker compose exec postgres psql -U "$DB_USER" -d "$DB_NAME"` (values from `.env`) |
| List Kafka topics | `docker compose exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:29092 --list` |
| Free disk space used by old builds | `docker builder prune -f` and `docker image prune -f` |

Service names are fixed: `frontend`, `node-api` (auth), `java-api` (order),
`java-worker` (executor), `postgres`, `kafka`, `mailpit`, `market-mock`.

## When the compose file itself must change

Find the spots with `grep -n "<<CHANGE>>" docker-compose.yml`.

| Situation | Edit |
|---|---|
| A second Node API, Java API or worker | Copy that service block, rename the service and its `.env` prefix, add the new keys to `.env`, add the new name to `COMPOSE_PROFILES` |
| A service must wait for another | Add it under that service's `depends_on` |
| The worker does not depend on the Java API | Remove the tagged `java-api` line under `java-worker` |
| A different kind of service (Python, Go, Redis) | Add a new block and a Dockerfile; this template does not cover it |

## What goes wrong, and where to look

| Symptom | Likely cause | Step |
|---|---|---|
| `compose build requires buildx 0.17.0 or later` | Old buildx plugin | 1 |
| `required variable ... is missing a value` | Key not set in `.env` | 2, 6 |
| Build fails: folder or `package.json` not found | Wrong `*_DIR`, or wrong letter case | 3 |
| Node container restarts: `Cannot find module` | Wrong `NODE_API_START_CMD` | 3 |
| Java service fails on a missing changelog or resource | `pom.xml` reads outside the folder | 3 |
| Container stays `unhealthy` but its log looks fine | Wrong `*_HEALTH_PATH`, or the path needs a login | 3 |
| Service exits: configuration key not defined | A name missing from section 3 of `.env` | 4 |
| `Connection refused` to `localhost` in a log | A `localhost` value in `.env` | 4 |
| Login works, every later call is 401 | `JWT_SECRET` or issuer differs | 4 |
| Page loads, all data calls fail or return HTML | Frontend proxy paths | 5 |
| Browser calls `localhost:3000` from another machine | Address missing from `FRONTEND_URL_REWRITES` | 5 |
| `Could not resolve placeholder 'services...'` | Shared config folder not mounted | 3 |
| `Could not find artifact ...domain...` in a Java build | In-repo library layout | 3 |
| `NOT RUNNABLE: ... has no Main-Class` | pom lacks `spring-boot-maven-plugin` | 3 |
| Browser console shows a CORS error | A call bypasses the frontend proxy, or wrong `PUBLIC_HOST` | 2, 5 |
| Schema does not exist | `JDBC_PARAMS` names a schema nothing creates | 6 |
| `Unknown topic` in a log | Topic missing from `KAFKA_TOPICS` | 7 |
| Worker crash-loops on missing tables at first start | It started before the migration | 8 |

## Limits

- A healthy start does not prove every screen works: do step 10 for your
  application.
- Covers Node (npm), Java (Maven or Gradle wrapper) and npm-built single-page
  frontends. Yarn, pnpm, server-side rendering and other languages need changes.
- The health check uses `wget` and `nc`, which the default Alpine images include.
  A different `RUNTIME_IMAGE` may not.
- One machine, no TLS. For HTTPS, put a reverse proxy or load balancer in front
  and set `PUBLIC_SCHEME=https`.
- Kafka UI has no login, so it is published on `127.0.0.1` only.
