# Load qualification

The specification plans for 300 invited members, 150 items in two rating
dimensions and 50 people rating at the same time, with short pauses as a
person makes them. The target is a 95th percentile below two seconds for one
confirmed save, and no confirmed answer may be lost. This page records how
that was measured and what was found.

## Method

`inst/qa/load-fixture-postgres.R` builds the study through the services: 300
members in two groups, 150 items with the dimensions relevance and clarity,
300 response fields per questionnaire. The first round is answered and
submitted by all 300 members (90 000 responses), analysed, its feedback
released and assigned; the second round is open.

`inst/qa/load-browser-postgres.R` opens one Chromium page per participant.
Each page has its own identity and its own database connection under the
restricted application role, as a person behind the gateway would. A script
in the page behaves like that person: it opens the second round, which shows
the person's previous answers and the panel results beside every item, then
for every field waits one to four seconds, chooses a rating, and waits until
the field states that the save was confirmed. It moves through the blocks of
ten fields and submits. Sessions arrive over two minutes. The run passes only
if every answer a page saw confirmed is the stored answer and every
submission it saw confirmed exists.

Measured per run:

| Measure | Where it is taken |
|---|---|
| Save, from the entry to the confirmation on screen | in the page; includes the deliberate pause of 1.5 seconds before an automatic save |
| Save after the pause | the same minus the pause: what a person waits for |
| Save in the service and database | the application's technical log at level `info` |
| Block shown, submission confirmed | in the page |
| Processor load and memory of the application processes | sampled from the operating system every five seconds |
| Database connections, active statements, lock waits | `pg_stat_activity`, every five seconds |

All components ran on one machine (72 cores, 188 GB, R 4.6.1, Shiny 1.14.0,
PostgreSQL 17) over the loopback interface. TLS, the authentication gateway
and the latency of a wide-area network are not part of the measurement.

## Results

Runs of 2 and 3 October 2026 with 50 sessions; each used 50 members who had
not yet answered the second round. Run names are UTC times. Times in
milliseconds.

| Run | Processes | Sessions per process | Save after the pause, p50 / p95 / p99 | Next block, p50 / p95 | Submission, p50 / p95 | Processor load per process while rating, mean / busiest | Memory of all processes, peak | Target |
|---|---|---|---|---|---|---|---|---|
| `20261002T193730` | 4 | 12.5 | 396 / 2378 / 4090 | 1002 / 2042 | 312 / 885 | 57 % / 74 % | 9.5 GB | missed |
| `20261002T205807` | 4 | 12.5 | 315 / 2106 / 3374 | 906 / 2126 | 266 / 918 | 54 % / 70 % | 4.3 GB | missed |
| `20261002T212504` | 6 | 8.3 | 182 / 1276 / 2102 | 862 / 1704 | 315 / 396 | 38 % / 57 % | 4.8 GB | **met** |
| `20261002T224633` | 6 | 8.3 | 170 / 1275 / 2093 | 863 / 1662 | 307 / 495 | 38 % / 58 % | 4.8 GB | **met** |

The first run used the sources before visited fields were released
([ADR-026](adr/026-large-rounds-and-blocks.md)); it is listed because it
shows what that correction changed: memory, not the waiting time. The last
run repeated the six-process configuration on the committed code (recorded
as commit `27a2aeb`; its application code is that of `7a88a8f`) and gave the
same result.

In every run:

- all 50 sessions finished: 15 000 saves and 50 submissions were confirmed on
  screen, and every one of them was found stored with the value the page had
  entered. **No confirmed answer was lost**, in 60 000 saves over the four
  runs.
- no operation was refused or failed, no page reported an error and no output
  showed one;
- a save took 28 ms in the service and the database at the median, 39 to 48 ms
  at the 95th and 59 to 102 ms at the 99th percentile; a submission 214 to
  245 ms at the median;
- the first block was ready after 1.0 to 1.2 seconds at the median and 2.0 to
  2.7 seconds at the 95th percentile;
- the database held one connection per session (50 to 53 in all), at most one
  statement was running and at most three transactions were open at a sampling
  instant, and no statement waited for a lock;
- no background job was involved; the queue of the worker was empty.

Other work was running on the same machine during the runs.

## Conclusions

**The target is met with six application processes** for 50 people rating at
the same time, in both runs: 95 of 100 saves were confirmed within 1.3 seconds
after the pause, 99 of 100 within 2.1 seconds.

**The limit is the application process, not the database.** A Shiny process
answers one request at a time. Preparing a block of ten fields takes it about
a second, and everyone else whose session lives in that process waits for
that second. With 12.5 participants per process the 95th percentile was 2.1
seconds, just above the target, at 54 percent mean load; with 8.3 it was 1.3
seconds at 38 percent. The service and the database need 28 ms for a save
and were never waiting for each other.

**Planning values** for this hardware and a round of this size:

| Quantity | Value | Basis |
|---|---|---|
| Participants rating at the same time per application process | 8 | met at 8.3, missed at 12.5 |
| Application processes for 50 at the same time | 6 or 7 | measured with 6 |
| Memory per application process | 1 GB | 0.8 GB per process at the peak with six, 1.1 GB with four |
| Database connections | one per open session, plus the worker and administration | 53 at the peak |

A smaller round needs less: the time of a block depends on its fields, not on
the length of the round, but the share of block changes among all requests
does. Several processes need the gateway to send each account to one process
and a shared private export directory; see
[authentication](authentication.md#several-application-processes).

**Study management shares these processes.** Some of its operations on a
round of this size occupy their process for seconds: reading and verifying a
frozen snapshot 4.9 seconds, the data of a study report 11 seconds
([ADR-026](adr/026-large-rounds-and-blocks.md)). Participants whose sessions
live in that process wait for that time, and their entries are saved after
it; this was not part of the measured runs. Analysis, exports and reports
themselves run in the worker and do not affect participants.

**Not covered by these runs:** TLS, the authentication gateway and a
wide-area network between browser and server; browsers other than Chromium;
more than 50 sessions; several large studies at once; staff working during
the run; a database on another host.

## Repeat

```sh
DELPHYR_TEST_DB=true Rscript packages/delphyrApp/inst/qa/load-fixture-postgres.R
DELPHYR_TEST_DB=true DELPHYR_LOAD_SESSIONS=50 DELPHYR_LOAD_PROCESSES=6 \
  Rscript packages/delphyrApp/inst/qa/load-browser-postgres.R
```

Every run uses 50 members who have not yet answered the second round;
`DELPHYR_LOAD_OFFSET` selects them. The result is written to
`.checks/load-browser-<time>.json` with the samples beside it. Do not edit
the script while a run is in progress: R reads it as it goes.
