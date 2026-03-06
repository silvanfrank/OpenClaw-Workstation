# Guacamole + xrdp Alternative

This document captures a browser-first alternative to the current workstation stack.

Current production direction remains:
- `webtop` + OpenClaw in one container
- no migration planned right now

This is only a documented fallback option if desktop lag remains unacceptable.

## Why this option exists

The current stack streams a full Linux desktop in-browser. This can feel laggy under:
- limited CPU headroom
- limited memory/shared memory
- network jitter or proxy buffering

Guacamole + xrdp is an alternative browser-access model that uses RDP for the desktop session.

## Architecture (high level)

Browser -> Guacamole web app -> guacd -> xrdp -> Linux desktop session

Typical deployment units:
- `guacamole` (web app)
- `guacd` (protocol proxy)
- `postgres` or `mysql` (Guacamole auth/session DB)
- workstation host/container running `xrdp` + desktop environment

## Expected advantages

- Better interactive feel than VNC-like remoting in many desktop workloads
- Browser-based access is still possible
- Centralized auth/session model through Guacamole

## Expected tradeoffs

- More moving parts than the current single-container setup
- More operational complexity (DB, guacd, connection config)
- Linux desktop session setup for xrdp can require tuning

## When to revisit

Revisit this option only if all of the following are true:
- Current `webtop` setup remains laggy after standard tuning
- Browser-only access is still required
- Team accepts additional operational complexity

## Suggested pilot (small, time-boxed)

1. Stand up a test environment separate from production.
2. Configure one xrdp desktop target with the same VPS class.
3. Connect via Guacamole in Chrome and compare:
   - typing latency
   - window drag smoothness
   - reconnect stability
4. Keep whichever stack is measurably better with lower ops burden.

## Decision status

Not selected for now. Keep current setup unless performance issues justify a controlled pilot.
