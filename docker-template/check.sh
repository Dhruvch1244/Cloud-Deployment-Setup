#!/usr/bin/env bash
# Pre-flight check. Run from the repo root BEFORE `docker compose up`:
#     ./docker-template/check.sh
# Reads .env (or the file given as $1) and reports everything that would make the
# build or the start fail. Changes nothing.
set -u
ENV_FILE="${1:-.env}"
fail=0; warn=0
ok()   { printf '  \033[32mOK\033[0m    %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; fail=$((fail + 1)); }
note() { printf '  \033[33mWARN\033[0m  %s\n' "$*"; warn=$((warn + 1)); }
# value of KEY in the env file (inline comment and surrounding blanks removed)
val()  { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | tail -n 1 | cut -d= -f2- | sed -E 's/[[:space:]]+#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//; s/^"(.*)"$/\1/'; }
ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n 1)" = "$2" ]; }

echo "1. Tools"
if docker info >/dev/null 2>&1; then ok "Docker daemon is running ($(docker version --format '{{.Server.Version}}'))"
else bad "Docker daemon is not reachable (sudo systemctl start docker; is your user in the docker group?)"; fi
cv="$(docker compose version --short 2>/dev/null | sed 's/^v//')"
if [ -z "$cv" ]; then bad "docker compose plugin is not installed"
elif ver_ge "$cv" 2.24.0; then ok "Docker Compose $cv"
else bad "Docker Compose $cv is too old (need 2.24+)"; fi
bv="$(docker buildx version 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 | sed 's/^v//')"
if [ -z "$bv" ]; then bad "docker buildx plugin is not installed"
elif ver_ge "$bv" 0.17.0; then ok "buildx $bv"
else bad "buildx $bv is too old (need 0.17+): install a newer one into /usr/local/lib/docker/cli-plugins/docker-buildx"; fi

echo "2. $ENV_FILE"
if [ ! -f "$ENV_FILE" ]; then
  bad "$ENV_FILE not found: cp docker-template/.env.example .env"
  echo; echo "Result: $fail problem(s)."; exit 1
fi
left="$(grep -nE '^[A-Z_0-9]+=CHANGE_ME' "$ENV_FILE" | cut -d= -f1 | tr '\n' ' ')"
[ -z "$left" ] && ok "no CHANGE_ME values left" || bad "still CHANGE_ME: $left"
js="$(val JWT_SECRET)"
[ "${#js}" -ge 32 ] && ok "JWT_SECRET is ${#js} characters" || note "JWT_SECRET is shorter than 32 characters"
lh="$(grep -nE '^[A-Z_0-9]+=.*(localhost|127\.0\.0\.1)' "$ENV_FILE" | grep -vE '^[0-9]+:(PUBLIC_HOST|CORS_ORIGINS|FRONTEND_URL_REWRITES|FRONTEND_BUILD_ENV)=' | cut -d= -f1 | tr '\n' ' ')"
[ -z "$lh" ] && ok "no localhost addresses" || note "these point at localhost, which inside a container is the container itself: $lh"

profiles=",$(val COMPOSE_PROFILES),"
on() { case "$profiles" in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

dbh="$(val DB_HOST)"
case "$profiles" in *",localdb,"*) [ "$dbh" = postgres ] || note "profile localdb is on but DB_HOST is '$dbh' (the bundled database is reached as: postgres)" ;;
  *) [ "$dbh" = postgres ] && bad "DB_HOST=postgres but profile localdb is off: add localdb to COMPOSE_PROFILES or set the RDS endpoint" ;; esac

echo "3. Service folders (enabled profiles:$(echo "$profiles" | tr ',' ' '))"
check_dir() { # profile PREFIX marker-file(s) default-dir
  on "$1" || return 0
  local dir df; dir="$(val "$2_DIR")"; dir="${dir:-$4}"; df="$(val "$2_DOCKERFILE")"; df="${df:-Dockerfile}"
  [ -d "$dir" ] || { bad "$1: folder $dir does not exist (check $2_DIR; names are case-sensitive)"; return; }
  local app; app="$(val "$2_APP_DIR")"; local mod; mod="$(val "$2_MODULE")"
  local found=""; for m in $3; do { [ -f "$dir/$m" ] || [ -f "$dir/${app:-.}/$m" ]; } && found="$m"; done
  [ -n "$found" ] && ok "$1: $dir ($found)" || bad "$1: none of [$3] in $dir - wrong folder?"
  [ -f "$dir/$df" ] || bad "$1: $dir/$df missing: cp docker-template/dockerfiles/<type>.Dockerfile $dir/$df"
  [ -f "$dir/.dockerignore" ] || note "$1: no $dir/.dockerignore (cp docker-template/dockerfiles/dockerignore.sample $dir/.dockerignore)"
  case "$3" in *package.json*) [ -f "$dir/package-lock.json" ] || note "$1: no package-lock.json - the build falls back to the slower, unpinned npm install" ;; esac
  local xd xdest; xd="$(val "$2_EXTRA_DIR")"; xdest="$(val "$2_EXTRA_DEST")"
  if [ -n "$xd$xdest" ]; then
    { [ -n "$xd" ] && [ -n "$xdest" ]; } || bad "$1: set BOTH $2_EXTRA_DIR and $2_EXTRA_DEST, or neither"
    [ -z "$xd" ] || [ -d "$xd" ] || bad "$1: $2_EXTRA_DIR=$xd does not exist"
  elif [ -z "$app$mod" ] && [ -f "$dir/pom.xml" ] && grep -q '<directory>\.\./' "$dir/pom.xml"; then
    bad "$1: pom.xml reads a folder outside $dir ($(grep -o '<directory>\.\./[^<]*' "$dir/pom.xml" | head -n 1 | cut -d'>' -f2)): set $2_EXTRA_DIR / $2_EXTRA_DEST"
  fi
}
check_dir node-api    NODE_API    "package.json"              ./services/node-api
check_dir java-api    JAVA_API    "pom.xml gradlew"           ./services/java-api
check_dir java-worker JAVA_WORKER "pom.xml gradlew"           ./services/java-worker
check_dir frontend    FRONTEND    "package.json"              ./frontend
if on node-api; then
  d="$(val NODE_API_DIR)"; sc="$(val NODE_API_START_CMD)"
  sp="$(grep -oE '"start:prod"[[:space:]]*:[[:space:]]*"[^"]*"' "$d/package.json" 2>/dev/null | sed -E 's/.*:[[:space:]]*"(.*)"/\1/')"
  [ -z "$sp" ] || [ "$sp" = "$sc" ] || note "node-api: NODE_API_START_CMD is '$sc' but package.json start:prod is '$sp'"
fi

echo "4. Host ports"
port_free() { # label port
  [ -n "$2" ] || return 0
  if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$2\$"; then
    if docker ps --format '{{.Ports}}' 2>/dev/null | grep -q ":$2->"; then note "$1 port $2 is published by a running container (fine if it is this stack)"
    else bad "$1 port $2 is already used by another program"; fi
  else ok "$1 port $2 is free"; fi
}
on frontend && port_free frontend "$(val FRONTEND_PORT)"
on node-api && port_free node-api "$(val NODE_API_PORT)"
on java-api && port_free java-api "$(val JAVA_API_PORT)"
on localdb  && port_free postgres "$(val DB_HOST_PORT)"
on kafka    && port_free kafka    "$(val KAFKA_HOST_PORT)"

echo "5. Compose file"
if out="$(docker compose --env-file "$ENV_FILE" config --quiet 2>&1)"; then ok "docker compose config is valid"
else bad "docker compose config failed:"; echo "$out" | sed 's/^/          /' | head -n 12; fi

echo
if [ "$fail" -gt 0 ]; then echo "Result: $fail problem(s), $warn warning(s). Fix the FAIL lines, then run again."; exit 1; fi
echo "Result: ready ($warn warning(s)).  Next: docker compose up --build -d"
