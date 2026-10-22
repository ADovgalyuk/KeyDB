# KeyDB 6.3.7: blocking-client timeout cleanup

The incidents on 2026-09-30 and 2026-10-22 share one root cause: type-specific
unblocking cleanup resets `bpop.timeout` before the timeout-table entry is
removed. The key is `(timeout, client pointer)`, so the old key can outlive its
client. The fix removes the entry before type-specific cleanup.

The automated regression suite checks this invariant directly. It does not
depend on the allocator reusing a freed client or on reproducing a process hang.
Each case gets a fresh server and is run with both one and four server threads.

## Automated tasks

| Task | Scenario | Expected result |
|---|---|---|
| TC-30-01 | BLPOP with a finite timeout, then LPUSH | Reply contains the value; blocked clients and timeout entries both return to zero |
| TC-30-02 | BZPOPMIN with a finite timeout, then ZADD | Reply contains the member and score; both counters return to zero |
| TC-30-03 | XREAD BLOCK with a finite timeout, then XADD | Reply contains the new stream entry; both counters return to zero |
| TC-30-04 | Close the connection while BLPOP is blocked | Client is unblocked/freed; both counters return to zero |
| TC-22-01 | CLIENT UNBLOCK TIMEOUT on finite BLPOP | Nil reply; both counters return to zero |
| TC-22-02 | CLIENT UNBLOCK ERROR on finite BLPOP | UNBLOCKED error reply; both counters return to zero |
| TC-22-03 | CLIENT KILL on finite BLPOP | Client is removed; both counters return to zero |
| TC-22-04 | Reuse one connection for 20 finite BLPOP/LPUSH cycles | No timeout entries accumulate after any cycle |
| TC-C-01 | Let BLPOP's finite timeout expire naturally | Nil reply; the timeout handler removes its own entry |
| TC-C-02 | BLPOP with timeout zero, then LPUSH | No timeout entry is created; data unblocks the client |
| TC-C-03 | Close a client blocked in WAIT after a write | WAIT cleanup still removes its timeout entry |

Every case checks that PING still succeeds after cleanup. Synchronization uses
the blocked-client counter, rather than fixed sleeps. There are 11 scenarios
and two thread configurations, for a total of 22 cases.

Run from the repository root after building:

```sh
make -j4 BUILD_TLS=yes
./runtest --single unit/blocked-timeout-cleanup --clients 1 --timeout 120 --quiet
```

The unit is registered in `tests/test_helper.tcl`, so it also participates in
the regular test program. CI runs it as a separate required step before the
existing broad test step; failures are not ignored.

Run the related suites as an additional check:

```sh
./runtest --single unit/type/list --single unit/type/zset \
  --single unit/type/stream --single unit/wait \
  --clients 4 --timeout 180 --quiet
```

## Release validation tasks

- [ ] Run the 22 regression cases on the release build for Ubuntu 22.04.
- [ ] Run the same cases on the release build for Oracle Linux 8.
- [ ] Run the related list, zset, stream and WAIT suites on each target build.
- [ ] In an isolated active-replica/multimaster staging deployment, exercise
      reconnects and full resynchronization while clients use finite blocking
      commands. Once clients finish, require both `blocked_clients:0` and
      `clients_in_timeout_table:0`, successful PING and continued replication.

The automated suite verifies the cleanup defect and its control paths. Passing
it does not establish that every possible cause of a KeyDB hang is eliminated.
