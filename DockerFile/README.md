# DockerFile: generic Dockerfiles and Docker Compose

Four Dockerfiles, one `docker-compose.yml` and a helper script. You do not edit
any of them: every setting comes from a `.env` file in your repository root.

| File | Use |
|---|---|
| `auth-service/Dockerfile` | Auth service (any npm / NestJS service) |
| `order-service/Dockerfile` | Order service (Spring Boot, Maven or Gradle wrapper) |
| `executor-service/Dockerfile` | Executor service (Spring Boot, Maven or Gradle wrapper) |
| `frontend/Dockerfile` | Angular / React frontend, served by nginx |
| `docker-compose.yml` | Starts everything; reads `.env` |
| `run.sh` | Shortcuts: build one at a time, start, clean run |

Image names are standard: `frontend`, `auth-service`, `order-service`,
`executor-service`.

Run every command from the root of **your** repository, on a branch.

## 1. Rename your existing Docker files

Nothing is deleted; your files become `*.999`. To go back, remove the suffix.

```bash
find . \( -name node_modules -o -name .git -o -name DockerFile -o -name target -o -name dist \) -prune -o \
  -type f \( -iname 'Dockerfile*' -o -name '.dockerignore' -o -iname '*compose*.yml' -o -iname '*compose*.yaml' \) \
  ! -name '*.999' -exec mv -n {} {}.999 \;
```

## 2. Copy the generic files into place

Copy this `DockerFile` folder into your repository root (keep the name), then:

```bash
cp DockerFile/docker-compose.yml .
cp DockerFile/auth-service/Dockerfile      <your-auth-service-folder>/Dockerfile
cp DockerFile/order-service/Dockerfile     <your-order-service-folder>/Dockerfile
cp DockerFile/executor-service/Dockerfile  <your-executor-service-folder>/Dockerfile
cp DockerFile/frontend/Dockerfile          <your-frontend-folder>/Dockerfile
```

Folder names must be spelled exactly as on disk (`Services` and `services` are
different folders on Linux).

## 3. Create `.env`

Create `.env` in your repository root and never commit it. The minimum content
is listed in the header of `docker-compose.yml` (step 3 there): project name,
what to run, `PUBLIC_HOST`, the database connection, `JWT_SECRET`, your four
folders and ports, the frontend address rewrites, and then every name your own
code reads (the keys of your `.env.example`, including the market-data URL and
key).

## 4. Build each image on its own first

One service at a time, so a problem shows up in one place:

```bash
docker build -t auth-service:latest      <your-auth-service-folder>
docker build -t order-service:latest     <your-order-service-folder>
docker build -t executor-service:latest  <your-executor-service-folder>
docker build -t frontend:latest          <your-frontend-folder>

docker images | grep -E "frontend|auth-service|order-service|executor-service"
```

If your versions are not the defaults (Node 20, Java 21, frontend Node 22), add
for example `--build-arg NODE_VERSION=22` or `--build-arg JAVA_VERSION=17`. The
build args are listed at the top of each Dockerfile.

A plain `docker build` knows nothing about your `.env`. If your project needs a
setting from it to build (a frontend build script that reads env values or a
folder outside the frontend, a Java service that depends on a library folder),
the plain command fails where this one works, because it passes those settings:

```bash
./DockerFile/run.sh build
```

It builds the same four images, with the same names, one at a time, and stops
at the first failure. All four must build before you go on.

## 5. Start everything with Compose

Compose uses the same image names, so the images from step 4 are the ones that run.

```bash
docker compose up -d
docker compose ps
```

| Task | Command |
|---|---|
| Follow one service | `docker compose logs -f order-service` |
| Apply a change in `.env` | `docker compose up -d order-service` |
| Rebuild one service after a code change | `docker compose up -d --build frontend` |
| Stop, keep the data | `docker compose down` |
| Stop and DELETE bundled database / Kafka data | `docker compose down -v` |

## 6. Clean run, once everything works

Stop, delete the images, build fresh, start. Use it before every real run so no
old image is reused.

```bash
./DockerFile/run.sh clean
```

which runs:

```bash
docker compose down
docker image prune -af
docker compose up --build -d
```

`docker image prune -af` deletes **every** image on the machine that no running
container uses, including other projects' images and the Postgres and Kafka
images (they are downloaded again). On a server shared with other teams, agree
on it first.

The prune is a command and not a step inside `docker-compose.yml` because
Compose builds the images before it starts any container: a prune started by
Compose would delete the images it has just built.

## If something fails

| What you see | Likely cause |
|---|---|
| `required variable ... is missing a value` | That key is not in `.env` |
| Build fails: folder or `package.json` / `pom.xml` not found | Wrong `*_DIR` in `.env`, often the letter case |
| Container stays `unhealthy` but its log looks fine | Wrong `*_HEALTH_PATH`, or that URL needs a login; set it empty |
| A service exits: a configuration key is not defined | A name your code reads is missing from `.env` |
| `Connection refused` to `localhost` in a log | Use the service name (`auth-service`, `order-service`, `kafka`, `postgres`), not `localhost` |
| Login works, every later call returns 401 | `JWT_SECRET` differs between services |
| Page loads, calls go to `localhost:3000` | That address is missing from `FRONTEND_URL_REWRITES`, or `PUBLIC_HOST` is not what you typed in the browser |
| Orders are accepted but never fill | Market-data URL or key in `.env` is wrong or empty |
