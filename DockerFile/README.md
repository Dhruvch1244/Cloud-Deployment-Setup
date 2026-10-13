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
| `run.sh` | Clean run: prune images, build the four images, `docker compose up -d` |

Image names are standard: `frontend`, `auth-service`, `order-service`,
`executor-service`.

Run every command from the root of **your** repository, on a branch.

## The commands in short

```bash
# build each image on its own
docker build -t auth-service:latest      <your-auth-service-folder>
docker build -t order-service:latest     <your-order-service-folder>
docker build -t executor-service:latest  <your-executor-service-folder>
docker build -t frontend:latest          <your-frontend-folder>

# start everything in the background
docker compose up -d

# clean run: prune images, build the four images, docker compose up -d
./DockerFile/run.sh
```

The steps below explain each of them.

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

Defaults: Node 20 for the auth service, Java 21, Node 22 for the frontend. The
build args are listed at the top of each Dockerfile.

With other versions or ports, pass them as build args:

```bash
docker build -t auth-service:latest      --build-arg NODE_VERSION=22 --build-arg APP_PORT=3000  <your-auth-service-folder>
docker build -t order-service:latest     --build-arg JAVA_VERSION=17 --build-arg APP_PORT=8081  <your-order-service-folder>
docker build -t executor-service:latest  --build-arg JAVA_VERSION=17 --build-arg APP_PORT=8082  <your-executor-service-folder>
docker build -t frontend:latest          --build-arg NODE_VERSION=22                            <your-frontend-folder>
```

A plain `docker build` knows nothing about your `.env`. If your project needs a
setting from it to build (a frontend build script that reads env values or a
folder outside the frontend, a Java service that depends on a library folder),
build that image through Compose, which passes the settings and gives the image
the same name:

```bash
docker compose build auth-service
docker compose build order-service
docker compose build executor-service
docker compose build frontend
```

All four must build before you go on.

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

One command. It prunes first, builds the four images, and finishes with
`docker compose up -d`:

```bash
./DockerFile/run.sh
```

What it runs, in order:

```bash
docker compose stop            # an image in use cannot be deleted
docker image prune -af         # 1. PRUNE: delete all unused images
docker compose build auth-service       # 2. BUILD: one image at a time
docker compose build order-service
docker compose build executor-service
docker compose build frontend
docker compose up -d           # 3. UP: always the last step
```

Use it before every real run so no old image is reused. `./DockerFile/run.sh -y`
skips the question.

`docker image prune -af` deletes **every** image on the machine that no running
container uses, including other projects' images and the Postgres and Kafka
images (they are downloaded again). On a server shared with other teams, agree
on it first.

The prune is in the script and not inside `docker-compose.yml` because Compose
builds the images before it starts any container: a prune started by Compose
would delete the images it has just built.

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
