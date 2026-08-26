# Chapter 01: Container Process Model

![Chapter 01 container lifecycle](diagram.svg)

## Key concepts

### What is a process?

A process is a running instance of a program.

It has its own execution state, including things such as:

- a process ID;
- memory mappings;
- open files;
- environment variables;
- CPU state;
- permissions;
- namespaces and other kernel-managed resources.

A process is not simply "a program stored at a location in memory." The program
is the executable code on disk; the process is the running instance created
when that program is executed.

### Where does Docker come in?

A Docker container is not an operating system or a virtual machine.

A container is a set of processes running on the host Linux kernel with
isolation provided by namespaces, cgroups, filesystem layers, and other kernel
features.

Every container has a process that appears as **PID 1 inside the container's
PID namespace**.

For example, in the official PostgreSQL image, the main process eventually
becomes the PostgreSQL server.

```text
container starts
    |
    v
entrypoint/setup
    |
    v
postgres
PID 1
```

- **PID 1** is the first process in the container's PID namespace and the
  process whose exit ends the container.
- **`command`** overrides the image's default command for this Compose service.
- **`exec`** replaces a shell wrapper with the real process so signals reach it
  directly.

The container is a process boundary, not a virtual machine. It shares the host
kernel while receiving isolated process, filesystem, and network namespaces.

## Goal

See that a container lives while its PID 1 process lives. Compare a long-lived
`sleep infinity` process with the command override used by Docker.

## Adds

The first chapter creates `public-a-test` without a network. This is the seed
service that later chapters progressively place into the lab.

## Checkpoint

## To Begin
### open your terminal and run
```bash 
bash scripts/compose-stage.sh 01 up -d
```

#### Inspect PID 1 directly
```bash
bash scripts/compose-stage.sh 01 ps
```

```text
NAME                            IMAGE         COMMAND            SERVICE         CREATED          STATUS          PORTS
docker-subnet-public-a-test-1   alpine:3.20   "sleep infinity"   public-a-test   16 minutes ago 
```

### confirm the main process running inside the container

```bash
bash scripts/compose-stage.sh 01 exec public-a-test ps
```

#### Your Terminal should show something similar
```text
PID   USER     TIME  COMMAND
    1 root      0:00 sleep infinity
   20 root      0:00 ps
```


### check the main process running in the container
```bash
bash scripts/compose-stage.sh 01 exec public-a-test sh -c 'tr "\\0" " " </proc/1/cmdline; printf "\\n"'
```
you should see 
```text
  sleep infinity
```

Explain why replacing `sleep infinity` with `true` makes the container exit.

Expected observation: `/proc/1/cmdline` contains `sleep infinity`, and `ps` can
show that it is the long-lived process. A command that exits normally gives the
container an exit status and Docker stops the service.

## Break it

Run `bash scripts/compose-stage.sh 01 run --rm public-a-test true`, then
compare that one-shot container with the long-running service.

Clean up with `bash scripts/compose-stage.sh 01 down` before moving on.


## Clean Up
cleaning up resources 
```bash 
bash scripts/compose-stage.sh 01 down -d
```
