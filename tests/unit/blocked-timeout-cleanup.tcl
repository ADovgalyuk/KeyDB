# A finite blocking timeout is part of the timeout-table key. Every way of
# unblocking a client must remove that key before resetting the blocking state
# or freeing the client. Check the table directly instead of relying on reuse
# of freed memory to turn a stale entry into a crash or a hang.

proc timeout_cleanup_wait_blocked {expected} {
    wait_for_condition 100 10 {
        [s blocked_clients] == $expected
    } else {
        fail "Expected $expected blocked clients, got [s blocked_clients]"
    }
}

proc timeout_cleanup_assert_empty {} {
    timeout_cleanup_wait_blocked 0
    assert_equal 0 [s clients_in_timeout_table]
    assert_equal PONG [r ping]
}

proc timeout_cleanup_run {scenario} {
    set rd [redis_deferring_client]
    set code [catch {
        assert_equal 0 [s clients_in_timeout_table]
        $rd client id
        set id [$rd read]

        switch -- $scenario {
            list-data - zset-data - stream-data {
                switch -- $scenario {
                    list-data { $rd blpop timeout:list 30 }
                    zset-data { $rd bzpopmin timeout:zset 30 }
                    stream-data { $rd xread block 30000 streams timeout:stream $ }
                }
                timeout_cleanup_wait_blocked 1
                assert_equal 1 [s clients_in_timeout_table]
                switch -- $scenario {
                    list-data {
                        r lpush timeout:list value
                        assert_equal {timeout:list value} [$rd read]
                    }
                    zset-data {
                        r zadd timeout:zset 1 value
                        assert_equal {timeout:zset value 1} [$rd read]
                    }
                    stream-data {
                        set stream_id [r xadd timeout:stream * field value]
                        assert_equal [list [list timeout:stream [list [list $stream_id {field value}]]]] [$rd read]
                    }
                }
            }
            unblock-timeout - unblock-error - client-kill - disconnect {
                $rd blpop timeout:list 30
                timeout_cleanup_wait_blocked 1
                assert_equal 1 [s clients_in_timeout_table]
                switch -- $scenario {
                    unblock-timeout {
                        assert_equal 1 [r client unblock $id timeout]
                        assert_equal {} [$rd read]
                    }
                    unblock-error {
                        assert_equal 1 [r client unblock $id error]
                        assert_error {UNBLOCKED*} {$rd read}
                    }
                    client-kill {
                        assert_equal 1 [r client kill id $id]
                    }
                    disconnect { $rd close }
                }
            }
            natural-timeout {
                $rd blpop timeout:list 0.1
                assert_equal {} [$rd read]
            }
            infinite-timeout {
                $rd blpop timeout:list 0
                timeout_cleanup_wait_blocked 1
                assert_equal 0 [s clients_in_timeout_table]
                r lpush timeout:list value
                assert_equal {timeout:list value} [$rd read]
            }
            wait-disconnect {
                $rd set timeout:write value
                assert_equal OK [$rd read]
                $rd wait 1 30000
                timeout_cleanup_wait_blocked 1
                assert_equal 1 [s clients_in_timeout_table]
                $rd close
            }
            reblock {
                for {set i 0} {$i < 20} {incr i} {
                    $rd blpop timeout:list 30
                    timeout_cleanup_wait_blocked 1
                    assert_equal 1 [s clients_in_timeout_table]
                    r lpush timeout:list $i
                    assert_equal [list timeout:list $i] [$rd read]
                    timeout_cleanup_assert_empty
                }
            }
            default { fail "Unknown timeout cleanup scenario: $scenario" }
        }
        timeout_cleanup_assert_empty
    } result options]
    catch {$rd close}
    return -options $options $result
}

tags {timeout network} {
    foreach threads {1 4} {
        foreach scenario {
            list-data zset-data stream-data
            unblock-timeout unblock-error client-kill disconnect
            natural-timeout infinite-timeout wait-disconnect reblock
        } {
            test "Timeout table cleanup: $scenario ($threads server threads)" {
                # Start each case with its own server, so a regression cannot
                # leave dangling entries that interfere with later cases.
                start_server [list overrides [list server-threads $threads save {} appendonly no]] {
                    timeout_cleanup_run $scenario
                }
            }
        }
    }
}
