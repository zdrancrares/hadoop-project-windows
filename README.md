# Hadoop Inverted Index — Windows Standalone Setup

A complete, single-machine Hadoop MapReduce project that builds an **inverted index** over 15 classic literature texts from Project Gutenberg. Runs entirely in Docker containers on Windows via WSL2, no LAN networking or cross-machine configuration required.

> Originally adapted from a distributed macOS-master / Windows-worker setup. This is the standalone Windows-only version: everything (HDFS namenode, datanode, YARN resourcemanager, nodemanager, history server) runs in five Docker containers on the same machine.

---

## Table of Contents

1. [What is Hadoop?](#what-is-hadoop)
2. [What is HDFS?](#what-is-hdfs)
3. [What is MapReduce / YARN?](#what-is-mapreduce--yarn)
4. [Project Architecture](#project-architecture)
5. [What InvertedIndex.java Does](#what-invertedindexjava-does)
6. [Prerequisites](#prerequisites)
7. [Quick Start](#quick-start)
8. [Detailed Step-by-Step Setup](#detailed-step-by-step-setup)
9. [Helper Scripts Explained](#helper-scripts-explained)
10. [Configuration Details (`hadoop.env`)](#configuration-details-hadoopenv)
11. [Web UIs (localhost ports)](#web-uis-localhost-ports)
12. [What Was Modified to Make It Work](#what-was-modified-to-make-it-work)
13. [Sample Output](#sample-output)
14. [Troubleshooting](#troubleshooting)

---

## What is Hadoop?

**Apache Hadoop** is an open-source framework for distributed storage and distributed processing of very large datasets across clusters of computers. It was designed around two key ideas:

- **Move computation to the data, not the other way around.** Network bandwidth is the bottleneck in big-data processing — Hadoop runs your program on the same machine that stores the data, instead of streaming terabytes across the network.
- **Build reliability in software, not hardware.** Hadoop assumes individual machines will fail, and replicates data + reassigns work automatically so the cluster keeps running.

A Hadoop cluster has two main subsystems:

| Subsystem | Purpose |
|-----------|---------|
| **HDFS** (Hadoop Distributed File System) | Stores files across many machines, with redundancy |
| **YARN** (Yet Another Resource Negotiator) | Schedules and runs distributed compute jobs |

On top of YARN, you run programming models like **MapReduce**, Spark, Tez, etc. This project uses classic MapReduce.

## What is HDFS?

HDFS splits each file into large fixed-size **blocks** (default 128 MB; in this project we use 512 KB so even small books generate multiple splits) and stores each block on one or more **DataNodes**. A central **NameNode** keeps the metadata: which file is made of which blocks, where each block lives.

In this project:
- **`namenode` container** = NameNode (metadata only, no actual data)
- **`datanode` container** = DataNode (actual block storage on disk)

Because it's a single-machine setup we only have one datanode, but the architecture is identical to a 1000-node production cluster.

## What is MapReduce / YARN?

**MapReduce** is a two-phase programming model:

1. **Map phase** — runs in parallel across many machines. Each map task processes one chunk (split) of input. For our inverted index, each map task reads one book (or one portion of a big book) and emits `(word, line-number)` pairs.
2. **Shuffle & sort** — Hadoop automatically groups all values that share the same key, sending them to the same reducer.
3. **Reduce phase** — for each unique key, the reducer receives all values. We use the reducer to merge the line numbers and produce the final entry: `word → (book1, line N, line M) (book2, line K) ...`

**YARN** is what schedules these map and reduce tasks onto the cluster:
- **`resourcemanager` container** = the brain. Knows about all available memory/CPU. Decides where each container runs.
- **`nodemanager` container** = the worker. Each machine has one. It launches map/reduce processes, monitors them, and reports back.
- **`historyserver` container** = stores logs and metrics for finished jobs so you can review them after the fact.

The unit of work is a **container** (not a Docker container — a YARN container, which is just a memory+CPU allocation that runs one JVM process).

---

## Project Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Docker Network                          │
│                                                                 │
│   ┌────────────┐    ┌────────────┐    ┌─────────────────┐       │
│   │  namenode  │    │  datanode  │    │ resourcemanager │       │
│   │  (HDFS     │◄──►│  (HDFS     │    │ (YARN scheduler)│       │
│   │  metadata) │    │  blocks)   │    │                 │       │
│   └─────┬──────┘    └─────┬──────┘    └────────┬────────┘       │
│         │                 │                    │                │
│         │                 │                    │                │
│         │           ┌─────▼──────┐    ┌────────▼────────┐       │
│         │           │ nodemanager│    │  historyserver  │       │
│         └──────────►│ (runs map/ │    │  (finished job  │       │
│                     │  reduce)   │    │   logs)         │       │
│                     └────────────┘    └─────────────────┘       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
       ▲          ▲          ▲          ▲          ▲
       │          │          │          │          │
   :9870      :9864      :8088      :8042      :8188
   (HDFS UI) (DN UI)  (YARN UI)  (NM UI)   (History UI)
```

All five services run as Docker containers on the same machine, on the same Docker bridge network. They reach each other by service name (`namenode`, `resourcemanager`, etc.) via Docker's built-in DNS — no IP addresses, no `extra_hosts`, no firewall rules needed.

---

## What InvertedIndex.java Does

An **inverted index** is the data structure that powers every search engine ever built. For each unique word in a text corpus, it stores the list of locations where the word appears. Searching for "Juliet" then becomes an instant lookup instead of a full scan of all books.

Our index output format is:

```
word    (book1.txt, line 23, line 87) (book2.txt, line 4) (book3.txt, line 156)
```

The implementation has three pieces:

### 1. The Mapper (`IndexMapper`)

- **Setup phase** (runs once per map task before any records): loads `stopwords.txt` from HDFS via Hadoop's distributed cache. Common words like `the`, `a`, `is`, `and` are added to a `HashSet` so the mapper can skip them during processing.
- **Map phase** (runs for each line of input):
  - Identifies which book this line came from (via `FileSplit.getPath().getName()`).
  - Increments a per-task line counter.
  - Tokenizes the line on punctuation/whitespace/digits.
  - For each token: lowercases it, skips tokens shorter than 2 characters, skips stopwords.
  - Emits `("word\tfilename", "lineNumber")` as the intermediate key/value.

Putting the filename in the *key* (not the value) is a deliberate design choice — it makes Hadoop's automatic sort group all entries of `(word, file)` together, so the reducer sees them as a contiguous run.

### 2. The Reducer (`IndexReducer`)

The reducer receives keys in **sorted order**. For each `(word, file)` group it deduplicates line numbers (so a word appearing twice on the same line is only listed once), sorts them, and formats them as `(file, line N, line M)`. When the word changes, it flushes the accumulated postings list as a single output record.

The streaming logic is a small state machine:
- Track the current word and current file.
- When the file changes within the same word, append the previous file's entry to the postings list.
- When the word changes, emit the completed postings list and start fresh.
- A `cleanup()` method handles the last word at end-of-input.

### 3. The Driver (`main`)

Wires everything up:
- Parses `--stopwords <hdfs-path>` argument.
- Registers the stopwords file in the distributed cache so every map task gets a local copy automatically.
- Sets mapper/reducer classes and key/value types (`Text, Text` throughout).
- Sets `setNumReduceTasks(1)` — one reducer means one alphabetically-sorted output file. With more reducers you'd get faster reduce phase but multiple unsorted output files that'd need a final merge.
- Sets input and output paths and submits the job to YARN.

---

## Prerequisites

- **Windows 10/11** with WSL2 enabled
- **Docker Desktop for Windows** with WSL2 backend (in Docker Desktop settings: *Use the WSL 2 based engine*)
- **WSL2 Ubuntu** (or any Linux distro inside WSL)
- At least **8 GB RAM** allocated to Docker (the cluster wants 4 GB, plus overhead for containers + Java)
- ~5 GB free disk space

Inside WSL:
```bash
sudo apt update && sudo apt install -y git curl
```

Docker should already be available inside WSL if Docker Desktop is set up correctly:
```bash
docker --version
docker compose version
```

---

## Quick Start

If you just want the thing running, top-to-bottom:

```bash
# Clone
git clone https://github.com/zdrancrares/hadoop-project-windows.git
cd hadoop-project-windows

# Download books (~15 MB across 15 texts)
chmod +x download_books.sh
./download_books.sh

# Start the cluster
docker compose up -d

# Wait for everything to be healthy (~60 sec)
sleep 60
docker ps        # all 5 containers should be (healthy)

# Copy code + data into the namenode container
docker cp InvertedIndex.java namenode:/root/
docker cp stopwords.txt namenode:/root/
docker cp books namenode:/root/

# Enter the namenode and run the job
docker exec -it namenode bash
```

Inside the namenode container:

```bash
cd /root
javac -cp $(hadoop classpath) -encoding UTF-8 InvertedIndex.java
jar cf invertedindex.jar InvertedIndex*.class
hdfs dfsadmin -safemode leave
hdfs dfs -mkdir -p /input
hdfs dfs -put books/*.txt /input/
hdfs dfs -put stopwords.txt /
hdfs dfs -rm -r -f /output
hadoop jar /root/invertedindex.jar InvertedIndex --stopwords hdfs:///stopwords.txt /input /output
hdfs dfs -cat /output/part-r-00000 | head -30
```

In a separate browser tab, open <http://localhost:8088> to watch the YARN job progress live.

---

## Detailed Step-by-Step Setup

### Step 1 — Clone the repository

```bash
cd ~
git clone https://github.com/zdrancrares/hadoop-project-windows.git
cd hadoop-project-windows
```

### Step 2 — Download the books

The books are not committed to the repo (they'd bloat it). The `download_books.sh` script fetches them from Project Gutenberg:

```bash
chmod +x download_books.sh
./download_books.sh
```

This creates a `books/` directory containing 15 `.txt` files:

| File | Author |
|------|--------|
| `alice_in_wonderland.txt` | Lewis Carroll |
| `anna_karenina.txt` | Leo Tolstoy |
| `crime_and_punishment.txt` | Fyodor Dostoevsky |
| `don_quixote.txt` | Miguel de Cervantes |
| `dorian_gray.txt` | Oscar Wilde |
| `dracula.txt` | Bram Stoker |
| `frankenstein.txt` | Mary Shelley |
| `moby_dick.txt` | Herman Melville |
| `monte_cristo.txt` | Alexandre Dumas |
| `pride_and_prejudice.txt` | Jane Austen |
| `romeo_and_juliet.txt` | William Shakespeare |
| `sherlock_holmes.txt` | Arthur Conan Doyle |
| `tale_of_two_cities.txt` | Charles Dickens |
| `the_odyssey.txt` | Homer |
| `war_and_peace.txt` | Leo Tolstoy |

### Step 3 — Start the Docker cluster

```bash
docker compose up -d
```

This starts five containers defined in `docker-compose.yml`:

| Container | Image | Role |
|-----------|-------|------|
| `namenode` | `asergiu/ubb:hadoop-namenode` | HDFS metadata server |
| `datanode` | `asergiu/ubb:hadoop-datanode` | HDFS block storage |
| `resourcemanager` | `asergiu/ubb:hadoop-resourcemanager` | YARN scheduler |
| `nodemanager` | `asergiu/ubb:hadoop-nodemanager` | YARN worker |
| `historyserver` | `asergiu/ubb:hadoop-historyserver` | Job history archive |

Verify they all came up:

```bash
docker ps
```

You should see all 5 with `Up X minutes (healthy)`. If any are still `(health: starting)`, wait another 30 seconds — the services check each other in a chain (datanode waits for namenode, resourcemanager waits for namenode, etc.) and need time to fully initialize.

### Step 4 — Copy your code and data into the namenode container

The job needs three inputs: the compiled jar, the stopwords file, and the books. We'll put them all in `/root` inside the namenode container so the rest of the commands are simple.

From WSL (not inside any container):

```bash
docker cp InvertedIndex.java namenode:/root/
docker cp stopwords.txt namenode:/root/
docker cp books namenode:/root/
```

### Step 5 — Enter the namenode container

```bash
docker exec -it namenode bash
```

Your prompt will change to something like `root@a1b2c3d4e5f6:~#`. Everything after this happens **inside the container** until you `exit`.

### Step 6 — Compile InvertedIndex.java into a JAR

```bash
cd /root
javac -cp $(hadoop classpath) -encoding UTF-8 InvertedIndex.java
jar cf invertedindex.jar InvertedIndex*.class
```

**Explanation:**
- `hadoop classpath` prints all the JARs Hadoop needs on the classpath (HDFS, YARN, MapReduce client libs).
- `$(hadoop classpath)` substitutes that output into the `-cp` flag.
- `-encoding UTF-8` matters because the books contain accented characters (Dostoevsky, Tolstoy, Dumas).
- `jar cf invertedindex.jar InvertedIndex*.class` packages the three generated `.class` files (the driver, the mapper inner class, the reducer inner class) into a JAR.

### Step 7 — Leave HDFS safe mode

```bash
hdfs dfsadmin -safemode leave
```

After a fresh start, HDFS sometimes stays in **safe mode** — a read-only state where it's checking block reports from datanodes. We force it out so we can write files.

### Step 8 — Upload input data to HDFS

```bash
hdfs dfs -mkdir -p /input
hdfs dfs -put books/*.txt /input/
hdfs dfs -put stopwords.txt /
```

The `hdfs dfs` command is HDFS's equivalent of Unix `ls`, `cp`, `mv`, etc. Here:
- `-mkdir -p /input` creates the input directory in HDFS (not on the container's local filesystem).
- `-put books/*.txt /input/` uploads each book.
- `-put stopwords.txt /` uploads stopwords to the HDFS root.

Verify the uploads:

```bash
hdfs dfs -ls /input
hdfs dfs -ls /
```

### Step 9 — Clear any old output

```bash
hdfs dfs -rm -r -f /output
```

Hadoop refuses to run a job if the output directory already exists (this is a safety mechanism — otherwise a fat-fingered command could destroy hours of computation). The `-f` flag makes `-rm` not error if the path doesn't exist yet.

### Step 10 — Run the job

```bash
hadoop jar /root/invertedindex.jar InvertedIndex --stopwords hdfs:///stopwords.txt /input /output
```

Arguments:
- `/root/invertedindex.jar` — the JAR you built.
- `InvertedIndex` — the main class inside the JAR.
- `--stopwords hdfs:///stopwords.txt` — custom flag the driver parses; gets registered in the distributed cache.
- `/input /output` — the standard input and output HDFS paths.

Watch the progress in the terminal. After ~30 seconds you'll see:

```
map  0% reduce  0%
map 10% reduce  0%
map 50% reduce  0%
map 100% reduce  0%
map 100% reduce 100%
Job ... completed successfully
Counters: 54
...
```

You can also watch it live in your browser: <http://localhost:8088>.

### Step 11 — Inspect the results

```bash
hdfs dfs -ls /output
hdfs dfs -cat /output/part-r-00000 | head -30
```

`part-r-00000` is the output of reducer #0 (we only have one reducer, so all output is here). It's sorted alphabetically by word.

To extract the file to your filesystem:

```bash
# Inside the container
hdfs dfs -get /output/part-r-00000 /root/output.txt
exit
# Back in WSL
docker cp namenode:/root/output.txt ~/inverted_index_output.txt
```

---

## Helper Scripts Explained

### `download_books.sh`

Downloads 15 plain-text books from Project Gutenberg into `./books/`. Each download uses:

```bash
curl -s -L --retry 3 -o "books/<filename>.txt" "<gutenberg-url>"
```

Flags:
- `-s` (silent) — no progress bar
- `-L` (follow redirects) — Gutenberg uses 301 redirects to mirror servers
- `--retry 3` — retry transient network failures up to 3 times
- `-o <path>` — output to this file

Each line uses shell short-circuit logic — `&& echo "done" || echo "FAILED"` — so if a URL is unreachable the script keeps going instead of stopping.

### `run.sh`

A convenience wrapper that does steps 6-11 in one shot. Run it **inside the namenode container** after you've copied the books, stopwords, and `InvertedIndex.java` there.

It compiles, uploads everything to HDFS, removes old output, runs the job, and prints the first 30 lines of output. Useful for re-running quickly during development.

### `restart.sh`

A defensive cleanup script that:
1. Starts the cluster with `docker compose up -d`
2. Sleeps 60 seconds for services to come up
3. Patches `mapred-site.xml` *inside* the running containers to fix any hardcoded memory limits that don't match what the cluster can actually allocate (the `asergiu/ubb` images shipped with values like `4096`/`8192` which exceed our 4 GB cluster cap, so we sed-replace them to safer defaults at runtime).
4. Reminds you how to enter the namenode container.

You only need this if you're hitting the "job stuck in ACCEPTED forever" problem from outdated memory settings. With the corrected `hadoop.env` in this repo, the `sed` patches are no longer strictly necessary, but the script is kept for safety.

---

## Configuration Details (`hadoop.env`)

This file is loaded by every container and tells Hadoop how the cluster is configured. Key settings:

| Setting | Value | Purpose |
|---------|-------|---------|
| `CORE_CONF_fs_defaultFS` | `hdfs://namenode:9000` | Where HDFS lives — all clients connect here |
| `HDFS_CONF_dfs_blocksize` | `524288` (512 KB) | Small block size so even small books generate multiple splits, giving more parallelism |
| `YARN_CONF_yarn_nodemanager_resource_memory___mb` | `4096` | Total memory YARN can allocate (4 GB) |
| `YARN_CONF_yarn_nodemanager_resource_cpu___vcores` | `8` | Total vCores available |
| `MAPRED_CONF_mapreduce_map_memory_mb` | `1024` | Each map task gets 1 GB |
| `MAPRED_CONF_mapreduce_reduce_memory_mb` | `2048` | Each reduce task gets 2 GB |
| `MAPRED_CONF_mapreduce_map_java_opts` | `-Xmx768m` | JVM heap for map task (75% of container = standard guidance) |
| `MAPRED_CONF_mapreduce_reduce_java_opts` | `-Xmx1536m` | JVM heap for reduce task |

### The naming convention (this part is non-obvious!)

The `asergiu/ubb` images use a Python script (`envtoconf.py`) that converts environment variable names into XML properties via this rule:

| Env var pattern | Becomes |
|-----------------|---------|
| `single_underscore` | `.` (dot) |
| `double__underscore` | `_` (literal underscore) |
| `triple___underscore` | `-` (dash) |

So `YARN_CONF_yarn_nodemanager_resource_memory___mb` becomes the property `yarn.nodemanager.resource.memory-mb` in `yarn-site.xml`. Getting the underscores wrong means the property name is silently mangled and the value is ignored — which was the source of several bugs during this project's setup (see next section).

---

## Web UIs (localhost ports)

Once the cluster is running, all of these are available in your browser:

### `http://localhost:9870` — HDFS NameNode UI

The main HDFS dashboard. Tabs:
- **Overview**: storage capacity, number of files, configured replication, datanodes alive
- **Datanodes**: each datanode with its IP, capacity, last heartbeat
- **Datanode Volume Failures**: failed disks (should be empty)
- **Snapshot**: snapshot management
- **Startup Progress**: NameNode startup timing
- **Utilities → Browse the file system**: navigate `/input`, `/output`, etc. and download files

### `http://localhost:8088` — YARN ResourceManager UI

The job dashboard. This is the most useful UI when running jobs.
- **Cluster → About**: cluster info
- **Cluster → Nodes**: list of NodeManagers, their available memory/cores, containers running
- **Cluster → Applications**: list of all jobs (NEW, ACCEPTED, RUNNING, FINISHED, FAILED, KILLED)
- Click an application ID to see the **AM container**, **map tasks**, **reduce tasks**, their containers, the nodes they ran on, and direct links to logs

This is where you confirm jobs go from `ACCEPTED` → `RUNNING` → `FINISHED`. While running, you'll see live counters: containers allocated, memory used, progress %.

### `http://localhost:8042` — NodeManager UI

Per-NodeManager dashboard. Shows currently running containers on that specific node and its health status.

### `http://localhost:9864` — DataNode UI

Per-DataNode info: total/used capacity, block pool ID, version. Mostly useful for debugging HDFS issues.

### `http://localhost:8188` — Timeline / History Server UI

Where finished applications' logs and metrics live. After a job ends, click "History" in the ResourceManager UI and it'll redirect you here for the post-mortem.

---

## What Was Modified to Make It Work

Several things in the originally-cloned `asergiu/ubb` setup didn't quite work out of the box on Windows/WSL. Here's the full list of changes that made it run end-to-end:

### 1. Added port mappings in `docker-compose.yml`

The original file only exposed `9870` and `9000` (HDFS NameNode UI and RPC). The other web UIs were stuck inside the Docker network with no host port mapping, so `localhost:8088` returned `ERR_CONNECTION_REFUSED` from the browser.

Added:

```yaml
  datanode:
    ports:
      - 9864:9864
  resourcemanager:
    ports:
      - 8088:8088
  nodemanager:
    ports:
      - 8042:8042
  historyserver:
    ports:
      - 8188:8188
```

### 2. Fixed map task memory limits in `hadoop.env`

The original values:

```env
MAPRED_CONF_mapreduce_map_memory_mb=4096
MAPRED_CONF_mapreduce_map_java_opts=-Xmx3072m
```

Caused a **silent deadlock**. The cluster has 4 GB total. The ApplicationMaster uses ~1 GB. That leaves 3 GB free — but each map task needed 4 GB, which never fits, so YARN kept the AM running and never assigned any map containers. Jobs stayed in `ACCEPTED` state forever, showing `map 0% reduce 0%` indefinitely.

Changed to:

```env
MAPRED_CONF_mapreduce_map_memory_mb=1024
MAPRED_CONF_mapreduce_map_java_opts=-Xmx768m
```

Now: AM (1 GB) + 3 parallel map tasks (1 GB each) = 4 GB → fits perfectly.

### 3. Fixed environment variable naming (single vs. double underscores)

The original repo had:

```env
HDFS_CONF_dfs_client__use__datanode__hostname=false
HDFS_CONF_dfs_datanode_use__datanode__hostname=false
```

This is **broken**: double underscores produce a literal `_` in the XML property name, so the actual property generated was `dfs.client_use_datanode_hostname` (which Hadoop doesn't recognize and silently ignores).

The correct form is:

```env
HDFS_CONF_dfs_client_use_datanode_hostname=true
HDFS_CONF_dfs_datanode_use_datanode_hostname=true
```

(In the final standalone setup these aren't needed at all because cross-machine hostname resolution doesn't apply, but it was the cause of significant pain in the earlier distributed version.)

### 4. Removed all LAN-IP hardcoding

In the earlier distributed Mac/Windows setup, `hadoop.env` had `192.168.0.179` (Mac's IP) sprinkled everywhere as the address of namenode/resourcemanager/etc. For the standalone version these all became service names (`namenode`, `resourcemanager`) so Docker's internal DNS handles resolution — no external IPs needed.

### 5. No firewall rules needed

In the distributed setup we had to manually open ports 8040, 8041, 8042, 9866, 9867, 13562, 45454 on Windows Defender for cross-machine YARN traffic. Standalone, none of this is necessary because all traffic stays inside Docker's bridge network.

### 6. `BLOCKSIZE` tuned down

```env
HDFS_CONF_dfs_blocksize=524288
HDFS_CONF_dfs_namenode_fs___limits_min___block___size=524288
```

Default HDFS block size is 128 MB. Our books are 0.1–3 MB each, so a 128 MB block size means each book becomes one split → one map task → no parallelism. Setting blocks to 512 KB gives ~30 splits across 15 books → real parallel execution where you can see multiple map tasks running simultaneously in the YARN UI.

---

## Sample Output

After running the job, `/output/part-r-00000` looks something like:

```
abandon (anna_karenina.txt, line 4521) (crime_and_punishment.txt, line 2103) (dracula.txt, line 287)
abandoned       (alice_in_wonderland.txt, line 142) (frankenstein.txt, line 89, line 1203) (war_and_peace.txt, line 9421)
abbey   (pride_and_prejudice.txt, line 1834) (sherlock_holmes.txt, line 412)
...
juliet  (romeo_and_juliet.txt, line 14, line 67, line 89, line 112, line 156, line 189, ...)
...
sherlock        (sherlock_holmes.txt, line 4, line 23, line 78, line 145, ...)
```

Each line: `word<TAB>(book1, line N, line M) (book2, line K) ...`. Sorted alphabetically. Tens of thousands of unique words.

The job typically completes in ~30–60 seconds depending on machine speed, with counters like:

```
Map input records:    71546   (total lines across all books)
Map output records:   326908  (total (word, file) pairs emitted after stopword filtering)
Reduce input groups:  51111   (unique (word, file) combinations)
Reduce output records: 28243  (unique words in the final index)
```

---

## Troubleshooting

**Job stuck in `ACCEPTED` state, never progresses past `map 0% reduce 0%`**
Almost always a memory misconfiguration. Check `hadoop.env`:
- `mapreduce_map_memory_mb` ≤ `yarn_nodemanager_resource_memory___mb` minus 1 GB (AM overhead).
- After editing, do `docker compose down && docker compose up -d` to apply.

**`localhost:8088` returns connection refused**
Port mapping missing in `docker-compose.yml`. Verify with `docker ps` that you see `0.0.0.0:8088->8088/tcp` next to the resourcemanager container.

**HDFS in safe mode, can't write files**
```bash
docker exec -it namenode hdfs dfsadmin -safemode leave
```

**Containers keep restarting**
```bash
docker logs <container_name> 2>&1 | tail -50
```
will show the actual error. Common causes: namenode disk full, port already in use, corrupted volume from a previous run (try `docker compose down -v` to wipe volumes).

**"Output directory already exists" error when running job**
```bash
hdfs dfs -rm -r -f /output
```
You can also use the `run.sh` script which does this automatically.

**Want to start completely fresh**
```bash
docker compose down -v   # -v also removes volumes (wipes HDFS data)
docker compose up -d
sleep 60
# Then re-upload your books and stopwords
```

---

## Credits

- Base Docker images: [`asergiu/ubb:hadoop-*`](https://hub.docker.com/u/asergiu) (Universitatea Babeș-Bolyai)
- Texts: [Project Gutenberg](https://www.gutenberg.org/)
- Apache Hadoop 3.4.0
