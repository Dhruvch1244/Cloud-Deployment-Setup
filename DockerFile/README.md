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
# build each image: go INTO the service folder, then build with a dot at the end
cd <your-auth-service-folder>      && docker build -t auth-service:latest .      
cd <your-order-service-folder>     && docker build -t order-service:latest .     
cd <your-executor-service-folder>  && docker build -t executor-service:latest .  
cd <your-frontend-folder>          && docker build -t frontend:latest .          

# run everything: prune old images, build, and start in the background
./DockerFile/run.sh
```

The steps below explain each of them.

## 0. Before anything: Docker, buildx and Docker Compose on the Ubuntu VM

Three things must be available on the VM before any command here works. Check:

```bash
docker --version
docker buildx version       # must print a version, 0.17 or newer
docker compose version      # must print a version, 2.24 or newer
```

### The most common problem: `requires BuildKit`

If `docker build` prints this, **buildx is missing on your VM**:

```
DEPRECATED: The legacy builder is deprecated and will be removed in a future release.
...
the --mount option requires BuildKit.
```

Fix it with these commands. They add the buildx and Compose plugins for every
user of the VM, whichever way Docker itself was installed:

```bash
ARCH=$(uname -m); case "$ARCH" in x86_64) BX=amd64; DC=x86_64 ;; aarch64|arm64) BX=arm64; DC=aarch64 ;; esac
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -fsSL "https://github.com/docker/buildx/releases/download/v0.19.3/buildx-v0.19.3.linux-$BX" -o /usr/local/lib/docker/cli-plugins/docker-buildx
sudo curl -fsSL "https://github.com/docker/compose/releases/download/v2.32.4/docker-compose-linux-$DC" -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx /usr/local/lib/docker/cli-plugins/docker-compose

docker buildx version
docker compose version
```

Both must now print a version. Run your `docker build` again: the `DEPRECATED`
line is gone and the build goes on.

The same fix solves these two messages:

- `docker: 'compose' is not a docker command`
- `compose build requires buildx 0.17.0 or later`

### Docker itself is not installed

If `docker --version` says "command not found", install Docker from its
official Ubuntu packages (this includes both plugins, so the fix above is not
needed):

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### `permission denied` on the Docker socket

Let your user run Docker without `sudo`, then log out and in again (or run
`newgrp docker`):

```bash
sudo usermod -aG docker $USER
```

### Final check

All of these must work, without `sudo`:

```bash
docker run --rm hello-world
docker buildx version
docker compose version
```

The command is `docker compose` (with a space). The old `docker-compose` (with
a hyphen) is a different, outdated tool and is not used here.

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

One service at a time, so a problem shows up in one place. For each service:
**`cd` into its folder** (the one that now holds the `Dockerfile`), then run
`docker build -t <image> .` The dot at the end means "build from this folder".

```bash
cd <your-auth-service-folder>
docker build -t auth-service:latest .
cd -

cd <your-order-service-folder>
docker build -t order-service:latest .
cd -

cd <your-executor-service-folder>
docker build -t executor-service:latest .
cd -

cd <your-frontend-folder>
docker build -t frontend:latest .
cd -
```

`cd -` takes you back to the repository root. Check the four images:

```bash
docker images | grep -E "frontend|auth-service|order-service|executor-service"
```

Use exactly these image names: `auth-service`, `order-service`,
`executor-service`, `frontend`.

Defaults are Node 20 for the auth service, Java 21, and Node 22 for the
frontend. For other versions add a build arg before the dot, for example
`docker build -t order-service:latest --build-arg JAVA_VERSION=17 .`
The build args are listed at the top of each Dockerfile.

A plain `docker build` does not read your `.env`. If a build fails because it
needs a setting from it (a frontend build script that reads env values or a
folder outside the frontend, a Java service that depends on a library folder),
build that image from the repository root through Compose, which passes the
settings and gives the image the same name: `docker compose build frontend`.

All four must build before you go on.

## 5. Run everything

From the repository root, one command:

```bash
./DockerFile/run.sh
```

It does three things in this order:

1. **Prune**: stops this project's containers and deletes all unused images
   (`docker image prune -af`), so no old image is reused.
2. **Build**: builds the four images one at a time and stops at the first failure.
3. **Up**: `docker compose up -d`, always the last step.

You do not have to run `docker compose up` yourself: the script ends with it.
`./DockerFile/run.sh -y` skips the question before the prune.

`docker image prune -af` deletes **every** image on the machine that no running
container uses, including other projects' images and the Postgres and Kafka
images (they are downloaded again). On a server shared with other teams, agree
on it first.

The prune is in the script and not inside `docker-compose.yml` because Compose
builds the images before it starts any container: a prune started by Compose
would delete the images it has just built.

## 6. Look at it

| Task | Command |
|---|---|
| What runs, and is it healthy | `docker compose ps` |
| Follow one service | `docker compose logs -f order-service` |
| Restart one service after changing `.env`, without a full clean run | `docker compose up -d order-service` |
| Stop, keep the data | `docker compose down` |
| Stop and DELETE bundled database / Kafka data | `docker compose down -v` |

## If something fails

| What you see | Likely cause |
|---|---|
| `the --mount option requires BuildKit` or `DEPRECATED: The legacy builder is deprecated` during `docker build` | buildx is not installed on the VM: run the fix in step 0 ("The most common problem"), then check with `docker buildx version` |
| `docker: 'compose' is not a docker command` | The Compose plugin is not installed: same fix in step 0 |
| `compose build requires buildx 0.17.0 or later` | buildx is too old: same fix in step 0 |
| `required variable ... is missing a value` | That key is not in `.env` |
| Build fails: folder or `package.json` / `pom.xml` not found | Wrong `*_DIR` in `.env`, often the letter case |
| Container stays `unhealthy` but its log looks fine | Wrong `*_HEALTH_PATH`, or that URL needs a login; set it empty |
| A service exits: a configuration key is not defined | A name your code reads is missing from `.env` |
| `Connection refused` to `localhost` in a log | Use the service name (`auth-service`, `order-service`, `kafka`, `postgres`), not `localhost` |
| Login works, every later call returns 401 | `JWT_SECRET` differs between services |
| Page loads, calls go to `localhost:3000` | That address is missing from `FRONTEND_URL_REWRITES`, or `PUBLIC_HOST` is not what you typed in the browser |
| Orders are accepted but never fill | Market-data URL or key in `.env` is wrong or empty |
