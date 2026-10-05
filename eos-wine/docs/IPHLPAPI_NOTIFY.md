# iphlpapi interface/address change notifications (`patches/local/0102`)

Windows' `NotifyIpInterfaceChange()` and `NotifyUnicastIpAddressChange()` register a callback that the
system invokes whenever an IP interface or a unicast IP address is added, removed or modified, and
return a handle that `CancelMibChangeNotify2()` unregisters; Wine implemented neither — the first was
a pure stub (returned `NO_ERROR`, set `*handle = NULL`, never called the callback) and the second a
semi-stub that only fired when `InitialNotification != 0`, so the Eos start-up path (`Registering for
network changes...`, which registers both with `InitialNotification = FALSE`) never received a single
notification, while `CancelMibChangeNotify2()` was itself a stub and the returned handle was always
`NULL`.  `patches/local/0102-iphlpapi-notify-interface-changes.patch` adds a per-registration worker
thread in `dlls/iphlpapi/iphlpapi_main.c` that keeps the existing NSI change notification
(`NsiRequestChangeNotification()` on `NSI_IP_UNICAST_TABLE`, the same plumbing `NotifyAddrChange()`
uses) armed for IPv4, IPv6, or both families for `AF_UNSPEC`, re-enumerates `GetIpInterfaceTable()` /
`GetUnicastIpAddressTable()` on every wake and on a 1 s timeout, diffs the result against the previous
snapshot and reports `MibAddInstance` / `MibDeleteInstance` / `MibParameterNotification` (with a row
pointer) to the callback; `InitialNotification` is delivered synchronously with a `NULL` row exactly as
Windows documents, `CancelMibChangeNotify2()` stops the thread and frees the registration, and
`CloseHandle()` on the opaque handle fails as on Windows.  One deliberate simplification is labelled in
the patch: the NSI plumbing has no notification source for the interface table (the Linux netlink
socket watches `RTMGRP_IPV4_IFADDR`/`RTMGRP_IPV6_IFADDR` only), so interface changes that do not also
change the address table (pure link state, MTU, …) are detected by the periodic re-check instead of
being signalled immediately.  To verify, apply the patch to a build — it dry-runs cleanly on the
current base and `tools/apply_patches.sh` picks up `0102` after `0101` — and run Eos: the former
`fixme:iphlpapi:NotifyIpInterfaceChange ... stub` and `...NotifyUnicastIpAddressChange ... semi-stub`
lines must be gone, both calls must return a non-`NULL` handle, and adding/removing an address on a
host interface while Eos runs must produce the corresponding callback (Wine's own
`dlls/iphlpapi/tests/iphlpapi.c:test_NotifyUnicastIpAddressChange` must still pass); the expected
user-visible result is that the `SLPReg() failed with result -19` / `SDT Couldn't Create component`
burst no longer blocks start-up, the `recovered from hang after ~54 s` transient drops to the
Windows-like ~10 s and the Eos editor window opens normally (reaching ~10 s also needs the bundle's
`slpd` SLP service installed in the prefix — see `docs/API_DIFF.md` §6.1 — so check the handle/callback
log lines in addition to the start-up time).
