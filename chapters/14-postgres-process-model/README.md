# Chapter 14: PostgreSQL Processes and Job Control

![Chapter 14 PostgreSQL process relationships](diagram.svg)

## Key Concepts

### A container is a PID namespace

The container has its own process view. The process at PID 1 is the container's
main process, and its exit ends the container. In this stage, the custom
PostgreSQL entrypoint eventually uses `exec` so the real PostgreSQL server is
the supervised PID 1 process.

```text
container start
    |
    v
primary-lab-entrypoint
    |
    v
docker-entrypoint.sh
    |
    v
postgres becomes PID 1
```

### PostgreSQL is a process family

PostgreSQL uses a main server process plus separate OS processes for client
backends and background work. The exact list can vary by PostgreSQL version and
configuration, but it commonly includes:

```text
postgres                 main server
postgres: checkpointer   background process
postgres: walwriter      background process
postgres: autovacuum     background process
postgres: ...            one client backend per session
```

`pg_backend_pid()` returns the OS PID of the backend serving the current SQL
session. It is not necessarily the PID of the main server.

### PID and job ID are different identifiers

An OS process has a PID such as `42`. A shell gives jobs a shell-local job ID
such as `%1`.

```text
Ctrl-Z = ask the shell to suspend the foreground job
bg     = ask the shell to resume that job in the background
jobs   = list jobs known to this shell
fg %1  = bring shell job 1 back to the foreground
```

Shell job control is not a container persistence mechanism. It does not replace
PID 1 supervision, and it does not control PostgreSQL's internal backend and
worker relationships.

## Goal

Connect the Chapter 01 container PID 1 model to the PostgreSQL primary. Inspect
the server and backend processes, then practice `Ctrl-Z`, `bg`, `jobs`, and
`fg` with a disposable shell job.

By the end, you should be able to:

- identify the PostgreSQL process at container PID 1;
- relate `pg_backend_pid()` to a process in `ps -ef`;
- distinguish PostgreSQL background processes from shell jobs;
- explain why `exec` matters for container signal and exit handling;
- terminate one client backend without terminating the server.

## From Chapter 13

Chapter 13 added `postgres-primary` at `10.10.21.20` and verified its routed
TCP and SQL behavior. Chapter 14 adds no service, network, route, firewall rule,
or Compose setting. It uses the running primary as a process laboratory.

The same database remains the writable primary:

```text
postgres-primary
    PID 1: PostgreSQL main server
    TCP 5432
    db_a: 10.10.21.20
```

The fact that a client can reach TCP 5432 is a network observation. The process
tree below explains which PostgreSQL process handles that connection after it
arrives.

## What This Stage Adds

No topology change is introduced. This chapter adds a learner workflow for
observing three existing boundaries:

```text
container lifecycle
    |
    v
PostgreSQL PID 1 and child processes
    |
    v
client backend for each SQL session

separate shell
    |
    v
job IDs and Ctrl-Z/bg/fg
```

The process observations are made inside `postgres-primary`. The job-control
exercise uses a harmless `sleep` process and must not background the database
server itself.

## Progress

- [ ] I can show that PostgreSQL owns container PID 1.
- [ ] I can identify a client backend from `pg_backend_pid()` and `ps -ef`.
- [ ] I can distinguish a PID from a shell job ID.
- [ ] I can suspend, resume, and foreground a disposable shell job.
- [ ] I can terminate one client backend while the primary stays available.

## Tasks

### 1. Inspect container PID 1 and the PostgreSQL process family

**Predict:** PID 1 should be the PostgreSQL server rather than an unmanaged
shell. `ps -ef` should show the main server and several PostgreSQL background
processes.

**Run:**

```bash
bash scripts/compose-stage.sh 14 up -d --build --wait
bash scripts/compose-stage.sh 14 ps

bash scripts/compose-stage.sh 14 exec postgres-primary \
  ps -p 1 -o pid,ppid,stat,args

bash scripts/compose-stage.sh 14 exec postgres-primary ps -ef

bash scripts/compose-stage.sh 14 exec postgres-primary \
  sh -c 'tr "\\0" " " </proc/1/cmdline; printf "\\n"'
```

**Observe:** PID 1 should be the PostgreSQL main server, with a command that
includes the Compose settings such as `wal_level=replica`. `ps -ef` should show
the main server, checkpointer, background writer or walwriter, autovacuum, and
other PostgreSQL processes. The exact process names vary by image version.

**Explain:** The custom `lab-entrypoint.sh` sets routes and then executes the
official PostgreSQL entrypoint. The official entrypoint eventually executes
the requested `postgres` command. `exec` replaces wrappers instead of leaving
an intermediate shell as PID 1, so signals and the server exit status reach the
container lifecycle anchor.

### 2. Match a SQL session to its OS backend

**Predict:** A live `psql` session should have a PostgreSQL backend process in
the same container. Its PID should be different from the main server PID 1.

**Run:** Use two terminals. In terminal A, start an interactive SQL session:

```bash
bash scripts/compose-stage.sh 14 exec postgres-primary \
  psql -U labadmin -d labdb
```

At the `psql` prompt, run this and record the number:

```sql
SELECT pg_backend_pid();
```

Leave the session open. In terminal B, inspect the process list:

```bash
bash scripts/compose-stage.sh 14 exec postgres-primary ps -ef

bash scripts/compose-stage.sh 14 exec postgres-primary \
  psql -U labadmin -d labdb \
  -c 'SELECT pid, backend_type, state FROM pg_stat_activity ORDER BY pid;'
```

Return to terminal A and exit `psql` with `\q`.

**Observe:** The PID returned by `pg_backend_pid()` should correspond to a
`postgres: labadmin labdb ...` process in `ps -ef`. `pg_stat_activity` should
show the session as a client backend while it exists. Once `\q` is entered,
that backend should disappear.

**Explain:** PostgreSQL's main process accepts the connection and creates a
backend process for the session. The backend is an OS process in the container
PID namespace, while `pg_stat_activity` is PostgreSQL's view of the same
session. This is a process relationship, not shell job control.

### 3. Practice job control with a disposable process

**Predict:** `Ctrl-Z` should stop a foreground `sleep`. `bg` should resume it
as a background job, and `fg %1` should make it the foreground job again.
None of these operations should change `postgres-primary` or its PID 1.

**Run:** Open a disposable shell in the primary container:

```bash
bash scripts/compose-stage.sh 14 exec postgres-primary bash
```

Inside that shell, run:

```bash
sleep 600
```

Press `Ctrl-Z`, then run:

```bash
jobs -l
bg %1
jobs -l
fg %1
```

Press `Ctrl-C` to stop the foreground `sleep`, then leave the disposable shell:

```bash
exit
```

**Observe:** After `Ctrl-Z`, the shell should show a stopped job. After `bg
%1`, it should show a running background job. After `fg %1`, the terminal is
again occupied by `sleep` until `Ctrl-C` stops it.

**Explain:** The shell tracks the job as `%1`, while the Linux kernel tracks
the underlying `sleep` process with a PID. `Ctrl-Z` and `bg` affect the shell's
foreground process group. They do not suspend or resume PostgreSQL's internal
workers, and they do not make a process survive container shutdown.

## Expected Observations

```text
container PID 1
        |
        v
postgres main server
        |
        +--> checkpointer
        +--> walwriter
        +--> autovacuum
        +--> client backend for each SQL session
```

The identifiers have different scopes:

| Identifier | Owner | Example | Meaning |
|---|---|---|---|
| PID | Linux process namespace | `42` | An OS process identity. |
| `pg_backend_pid()` | PostgreSQL session | `42` | The backend serving one SQL session. |
| Job ID | Interactive shell | `%1` | A shell-local handle for a foreground/background job. |
| Container PID 1 | Container runtime | `1` | The process whose exit ends the container. |

The database can have many backend and worker PIDs while still having one
container PID 1. A shell's job table is not PostgreSQL's process tree.

## Checkpoint: Definition of Done

You are done when you can answer all of these:

1. Which process is container PID 1?
2. What process does `pg_backend_pid()` identify?
3. Why does one SQL session create a backend without replacing PID 1?
4. What is the difference between PID `42` and shell job `%1`?
5. What does `Ctrl-Z` do, and what does `bg` do?
6. Why should the database server itself not be started as an unmanaged shell
   background job?

The progress checklist should be complete, and the harmless `sleep` job should
have been stopped before leaving its shell.

## Break It

Terminate one client backend while leaving the PostgreSQL server and its
background processes untouched.

First ensure the SQL session from Task 2 is closed. Then use two terminals. In
terminal A, open a new session and record its backend PID:

```bash
bash scripts/compose-stage.sh 14 exec postgres-primary \
  psql -U labadmin -d labdb
```

At the prompt:

```sql
SELECT pg_backend_pid();
```

Leave `psql` open. In terminal B, replace `<BACKEND_PID>` with the number from
terminal A and send that client process a termination signal:

```bash
bash scripts/compose-stage.sh 14 exec -T -u postgres postgres-primary \
  kill -TERM <BACKEND_PID>
```

**Predict:** Terminal A should report that the server closed the connection.
PID 1 and PostgreSQL's background processes should remain alive, and a new SQL
session should still work.

**Observe:** Check the process tree and reconnect:

```bash
bash scripts/compose-stage.sh 14 exec postgres-primary \
  ps -p 1 -o pid,ppid,stat,args

bash scripts/compose-stage.sh 14 exec postgres-primary \
  psql -U labadmin -d labdb \
  -c 'SELECT pg_is_in_recovery(), current_database();'
```

The first command should still show PostgreSQL at PID 1. The second should
return `f` and `labdb`.

**Explain:** The killed process was one session backend, not the main server.
The server supervises the process family and can accept another connection.
This is different from using `Ctrl-Z`, which asks a shell to suspend a
foreground job.

**Recover:** Exit any remaining interactive `psql` session with `\q`. No
container recreation is required; opening a new session is the recovery for a
terminated client backend.

## Clean Up

Remove the resources for this cumulative stage:

```bash
bash scripts/compose-stage.sh 14 down
```

The named PostgreSQL volume is retained by this command. Use `down -v` only
when you intentionally want to delete the primary data and repeat first-time
initialization.

## Conclusion: Next Chapter

The PostgreSQL server is the container's PID 1 process, while sessions and
workers form a child process family. Shell job control is a separate interface
for managing disposable foreground and background jobs. The next chapter adds
`postgres-replica` and uses `pg_basebackup` plus WAL streaming to build a
physical standby across the routed database networks.
