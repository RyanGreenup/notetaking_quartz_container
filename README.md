# quartz config

This config describes the process of installing [quartz](https://quartz.jzhao.xyz/) using Docker or Podman.

## Introduction
There are two approaches to take:

  1. Live Serve the notes with Quartz
      - This simply involves modifying the docker compose below to call `npx quartz build --serve --port 8080`
  2. Build with Quartz and Copy to a directory served by Caddy
      - This is more reliable, but requires a rebuild every time the notes are updated.
      - Ocassionally the build for Quartz hangs, so `timeout` is used with a loop over `entr` so it only rebuilds when necessary.
## inotify limits

It may be necessary to increase the inotify limits on the host machine.

```bash
echo 256 | sudo tee /proc/sys/fs/inotify/max_user_instances
```

This can be made permanent with:

```bash
echo fs.inotify.max_user_instances=256 | sudo tee /etc/sysctl.d/40-max-user-watches.conf
sudo sysctl --system
```

See [journal:inotify_limits [Notes]](http://localhost:8923/doku.php?id=journal:inotify_limits)


## Caddyfile

Write a caddyfile that can serve the content. Ocassionally, particularly on large corpus, the server will crash, use Caddy instead:

```
# Move Admin port somewhere inconspicuous
{
    admin localhost:20191
}

# Serve the notes that are being rebuilt all the time
# No need for this, it will be down on every rebuild.
# :3820 {
#     root * ./public
#     try_files {path} {path}.html {path}/ =404
#     file_server
#     encode gzip
#
#     handle_errors {
#         rewrite * /{err.status_code}.html
#         file_server
#     }
# }

# Serve the Built Notes
:3818 {
    root * ./public_host
    try_files {path} {path}.html {path}/ =404
    file_server
    encode gzip

    handle_errors {
        rewrite * /{err.status_code}.html
        file_server
    }
}
```


## Dockerfile

The default install comes with a Dockerfile that can build the environment as well as run it. Here I've created a separate dockerfile that simply runs quartz in an isolated container:

```dockerfile
# Use Fedora as a base
FROM fedora:latest
# Install the dependencies
RUN dnf install -y caddy  nodejs-npm git
# Download Quartz
RUN git clone https://github.com/jackyzha0/quartz
# CD into Quartz
WORKDIR /quartz
# Copy in the Caddyfile
COPY Caddyfile .
# Install the dependencies
RUN npm install
# Initialize the Quartz environment
RUN npx quartz create -d "content" -X "new" -l "relative"

# The CMD / Entrypoint will be handled by the docker-compose.yml
```

This container will involve two builds of quartz, somewhat redundantly, however, it's easier than managing two dockerfiles so who cares.

## Docker Compose

### Run Quartz on it's own
#### Introduction
This is, by far, the simplest approach. However, Quartz crashes on large corpus, so it's not recommended for large notes.
#### Yaml File



```yaml
version: '3.8'

services:
  quartz_2:
    build: .
    container_name: quartz
    volumes:
      - $HOME/Notes/slipbox_tmp:/usr/src/app/content
    ports:
      - "3877:8080"
    restart: unless-stopped
    # The command to run
    command: ["npx", "quartz", "build", "--serve", "--port", "8080"]
```
#### Run the container

```bash
docker compose up -d
docker compose exec -it quartz_2 /bin/sh
```
### Quartz with Caddy
#### Outline


This approach is a bit more complex:

- Containers
    - Caddy
        - Serves the notes under `./public_host`
    - Quartz
        - Builds the notes under `./content`
        - After Quartz runs these contes are copied to `./public_host`
        - quartz runs every time a file under `./content` is changed.
- Scripts
    - `loop_quartz.sh`
        - This script uses `entr` to rerun `./run_quartz.sh` any time a file is changed
            - the `-d` flag is used to exit when a new file is added
                - A loop is used to rerun `entr` every time it exits
                    - Effectively watching old and new files in that directory and rebuilding the notes when necessary

        ```sh
        while :; do
            find ./content |\
                entr -d -n  \
                ./run_quartz.sh
        done
        ```
    - `run_quartz.sh`
        - This script runs with a timeout of 300 seconds
            - This is because Quartz ocassionally hangs
                - The timeout will kill the process and the loop will restart it
        - The script builds the notes in `./content` and copies `./public` to `./public_host` so Caddy can serve them.
            - Caddy cannot watch `./public/` as quartz will remove that each time it is rebuilt.

        ```sh
        timeout 300 /usr/bin/npx quartz build --concurrency 4 &&\
            cp -r public/* public_host/ &&\
            echo "BUILD DONE--------------------------------------------"
        ```

#### Docker Compose



##### Yaml

```yaml
version: '3.8'

services:
  quartz:
    build: .
    container_name: quartz
    volumes:
      # Notes only need to be readonly
      - /home/ryan/Notes/slipbox:/quartz/content:ro
      - ./data/public:/quartz/public
      - ./data/public_host:/quartz/public_host
    restart: unless-stopped
    # The command to run
    command: ["sh", "loop_quartz.sh"]
  caddy_server:
    build: .
    container_name: quartz_caddy_server
    volumes:
      - ./data/public:/public
      - ./data/public_host:/public_host
    ports:
      - "3877:8080"
    userns_mode: "keep-id"
    restart: unless-stopped
    # The command to run
    command: ["caddy", "run"]
```

##### Scripts

###### Loop Quartz
```sh
#!/bin/sh
while :; do
    find ./content |\
        entr -d -n  \
        ./run_quartz.sh
done
```
###### Run Quartz

```sh
#!/bin/sh
# build.sh
# Timeout will give up if this takes longer than the specified time
timeout 300 /usr/bin/npx quartz build --concurrency 4 &&\
    cp -r public/* public_host/ &&\
    echo "BUILD DONE--------------------------------------------"
```
## Running it

```sh
podman-compose rm --all
podman-compose up
```

```sh
docker compose rm --all
docker compose up
```







