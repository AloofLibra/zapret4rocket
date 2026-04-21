# AGENTS.md

## Purpose

This repository is a shell-based installer and management wrapper around `zapret2`, with:

- a custom `config.default`
- interactive maintenance menus
- strategy selection and locking
- shipped hostlists and fake payloads
- platform-specific patches for VPS, OpenWRT, Keenetic Entware, and Merlin
- an "orchestra" layer that tracks and pins working strategies
- a builder-first MVP layer that can generate and apply fixed strategies for selected profiles
- Lua modules for desync orchestration, grouping, lock management, and failure detection

Primary entrypoint:

- `z2r.sh`: main script for install, update, environment detection, config deployment, menu actions, and orchestrator lifecycle.

Secondary helper scripts:

- `z4r_test.sh`
- `user_test2.sh`
- `merlin_wan_restart_zapret.sh`

## Current Runtime Model

This project is no longer centered on `/opt/zapret`. The active target layout is `/opt/zapret2`.

Most runtime logic assumes these absolute paths:

- `/opt/zapret2/config`
- `/opt/zapret2/config.default`
- `/opt/zapret2/extra_strats/...`
- `/opt/zapret2/lists/...`
- `/opt/zapret2/files/fake/...`
- `/opt/zapret2/lua/...`
- `/opt/zapret2/init.d/...`

Normal flow:

1. `z2r.sh` detects OS and hardware.
2. It installs or refreshes upstream `zapret2`.
3. It deploys this repository's assets into `/opt/zapret2`.
4. It installs the custom config, extra strategy files, lists, fake payloads, Lua scripts, and orchestra state files.
5. It manages `zapret2` and the strategy orchestrator through an interactive menu.

Builder-first MVP flow:

1. The user explicitly starts discovery for a supported profile.
2. `lib/strategy_builder.sh` seeds a bounded candidate set, runs probes, and stores candidate/session metadata under `/opt/zapret2/extra_strats/cache/builder`.
3. Discovery remains pre-runtime intelligence only. The runtime stays on `circular_locked`; there is no online adaptive switching.
4. When a candidate is chosen, the builder appends a generated `--lua-desync ... strategy=N` block into the active profile config, updates the relevant manual lock, and that fixed strategy stays active until the user changes it.
5. The Web UI tracks discovery as an async background job per profile and reads status from builder cache state files.

## Layout

- `z2r.sh`: top-level orchestration script. Sources runtime modules from `zapret2/z2r_lib` after deployment, while this repository stores their source versions in `lib/`.
- `config.default`: main shipped `zapret2` config. This is now a large profile-driven config with `--lua-init`, `--lua-desync`, profile blocks, fallback blocks, blob declarations, and strategy numbering that other scripts depend on.
- `lib/ui.sh`: generic menu and terminal UI helpers.
- `lib/provider.sh`: ISP/provider and location detection, cache, and manual override.
- `lib/telemetry.sh`: telemetry enable/disable and stats sending.
- `lib/recommendations.sh`: hint database and provider-based recommendations.
- `lib/netcheck.sh`: connectivity tests, CDN tests, and YouTube cluster probing.
- `lib/premium.sh`: easter-egg and premium menu branches.
- `lib/strategies.sh`: active strategy status, orchestra lock helpers, per-profile strategy trial flow, custom RKN domain handling.
- `lib/submenus.sh`: menu wiring for strategies, provider, offload, and related actions.
- `lib/strategy_builder.sh`: builder-first MVP implementation. Owns bounded candidate generation for profiles `1` and `2`, config patching for generated strategy blocks, discovery sessions, saved candidate metadata, and builder JSON helpers for WebUI.
- `lib/actions.sh`: config reset, backup, firewall mode switch, UDP toggles, TLS blob switching, and other menu actions.
- `lists/`: shipped hostlists and ipsets.
- `fake/`: fake payload binaries, now including `custom_tls.bin`.
- `extra_strats/`: numbered strategy slots and special lists used by config and menu logic.
- `extra_strats/TCP/RKN/Discord.txt`: dedicated Discord-related list used by config and blob toggles.
- `orchestra/orchestrator.sh`: shell daemon that watches logs and maintains orchestration state under `/opt/zapret2/extra_strats/cache/orchestra`.
- `orchestra/locked.lua`: Lua lock adapter used by the config and orchestrator state.
- `lua/strategy-lock-manager.lua`: centralized lock/block state and hostname normalization.
- `lua/combined-detector.lua`: combined quality/failure logic that uses orchestration state.
- `lua/domain-grouping.lua`: grouping logic for related domains.
- `lua/silent-drop-detector.lua`: silent-drop detection.
- `webui/app.js`: browser control plane. Now includes embedded builder panels for supported profiles, async discovery polling, and candidate apply actions.
- `webui/styles.css`: WebUI layout and builder-specific responsive fixes.
- `webui/cgi-bin/_lib.sh`: CGI helper library. Exposes builder metadata, candidates, discovery status/results, and apply endpoints.
- `webui/cgi-bin/builder-meta.cgi`: builder metadata endpoint.
- `webui/cgi-bin/builder-candidates.cgi`: saved/generated candidate list endpoint for a profile.
- `webui/cgi-bin/discovery-start.cgi`: async discovery start endpoint.
- `webui/cgi-bin/discovery-results.cgi`: discovery status and latest results endpoint.
- `webui/cgi-bin/apply-candidate.cgi`: generated candidate apply endpoint.
- `webui/cgi-bin/active-generated.cgi`: active generated-strategy endpoint.
- `Entware/`: Entware/Keenetic startup and integration patches.

## Architecture Notes

The project now has two interacting layers:

- Shell/menu layer: deploys files, edits config, starts/stops services, and manually assigns strategies.
- Lua/orchestra layer: decides, tracks, groups, and locks strategies at runtime.

There is also a limited builder layer:

- Builder/discovery layer: generates bounded `zapret2`-compatible candidates for supported profiles, stores discovery state, and promotes one chosen candidate into a fixed manual strategy.

Important practical consequence:

- many changes that look "config-only" also affect shell menu actions
- many changes that look "shell-only" are actually constrained by Lua profile numbering and `strategy=N` semantics
- builder changes affect shell menus, CGI response contracts, WebUI rendering, and config-numbering assumptions at the same time

## High-Risk Areas

- `config.default` is structurally coupled to shell code. Menu actions and strategy helpers depend on exact markers, profile ordering, and recognizable patterns such as `--lua-desync=...strategy=N`.
- `lib/actions.sh` uses targeted `sed`/`awk` replacements against `/opt/zapret2/config`. Small wording changes in config blocks can silently break toggles.
- `lib/strategies.sh` derives max strategy counts from config content. If profile structure changes, strategy menus can go out of sync.
- `lib/strategy_builder.sh` patches live config by inserting generated blocks marked with `# Z2R_BUILDER_BEGIN profile=N` / `# Z2R_BUILDER_END profile=N`. Any change to profile boundaries, numbering rules, or `NFQWS2_OPT` structure can break builder apply/discovery.
- `z2r.sh` performs destructive operations on target machines, including removing or rebuilding `/opt/zapret2`.
- `orchestra/orchestrator.sh` assumes specific log patterns and state file locations. Renaming emitted messages or moving paths can break learning/locking.
- `lua/strategy-lock-manager.lua` is a shared source of truth for hostname normalization and lock/block state. Duplicating normalization elsewhere is likely to cause subtle bugs.
- Builder profile `1` is mixed `tls/http`, so any code that applies a generated strategy must keep both lock rows aligned; otherwise runtime behavior diverges by protocol.
- WebUI discovery is asynchronous and stateful. `webui/cgi-bin/_lib.sh` now relies on PID/state/log files under `/opt/zapret2/extra_strats/cache/webui-builder`; changing these paths or response shapes can break progress tracking.

## Editing Guidelines

- Preserve Bash compatibility and existing shell style. Do not introduce unnecessary dependencies.
- Prefer small, local changes in `lib/*.sh` or `lua/*.lua` rather than expanding `z2r.sh` unless the change is truly top-level.
- Treat `config.default` as an API surface for both shell and Lua code.
- Do not casually rename files or move assets. Many paths are hardcoded in shell, config, and Lua.
- Keep Russian comments and user-facing text consistent with surrounding code.
- When changing strategy counts or profile composition, verify all related menu/status code.
- When changing orchestration or lock behavior, inspect both shell and Lua sides before editing.
- Do not treat builder discovery as runtime orchestration. The intended model is still explicit manual choice of the final strategy.
- If you edit builder JSON or CGI responses, also inspect `webui/app.js` because it now polls and renders builder state live.
- If you edit `lib/strategy_builder.sh`, verify both config insertion markers and lock behavior for supported profiles.

## What To Check First For Typical Tasks

For install/bootstrap issues:

- `z2r.sh`
- `Entware/`
- `config.default`

For menu or toggle bugs:

- `lib/submenus.sh`
- `lib/actions.sh`
- `lib/ui.sh`

For strategy selection or status issues:

- `lib/strategies.sh`
- `config.default`
- `orchestra/orchestrator.sh`
- `lib/strategy_builder.sh` if the issue involves generated candidates or builder-applied strategies

For runtime adaptive behavior or locking bugs:

- `lua/strategy-lock-manager.lua`
- `lua/combined-detector.lua`
- `lua/domain-grouping.lua`
- `orchestra/locked.lua`

For blob or fake-payload issues:

- `config.default`
- `lib/actions.sh`
- `fake/`

For builder/discovery issues:

- `lib/strategy_builder.sh`
- `lib/submenus.sh`
- `webui/cgi-bin/_lib.sh`
- `webui/app.js`
- `webui/styles.css`

## Validation

There is no formal automated test suite in this repository.

Minimum validation after edits:

- read the affected shell or Lua file for quoting, path, and pattern regressions
- if `config.default` changed, re-check every `sed`, `awk`, `grep`, or profile-number assumption that touches the edited block
- if strategy counts changed, verify the matching limits in menu/status helpers
- if orchestration logic changed, verify path consistency across `z2r.sh`, `orchestra/`, `lua/`, and `config.default`
- if file names or asset paths changed, search the entire repo for stale references
- if builder logic changed, verify generated-strategy numbering is still contiguous inside each supported profile
- if builder discovery/WebUI changed, verify the CGI status contract for `running/completed/failed/idle` and re-check any polling assumptions in `webui/app.js`
- if profile `1` builder logic changed, verify lock synchronization for both `tls` and `http`

## Local Inspection Notes

- The repository content is largely Russian UTF-8 text. On Windows PowerShell it may display as mojibake if the console encoding is not UTF-8.
- This workspace is the source repository, not the deployed `/opt/zapret2` tree. Edit source files here unless you are intentionally debugging a live deployment copy.
