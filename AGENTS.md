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

Policy-runtime flow for builder profiles `1` and `2`:

1. Builder maintains a policy catalog under `/opt/zapret2/extra_strats/cache/policy/catalog/profiles`.
2. Manual apply for supported builder profiles writes profile/domain policy state JSON and rebuilds `/opt/zapret2/extra_strats/cache/policy/state/runtime_snapshot.lua`.
3. `nfqws2` loads `policy-state.lua`, `step-library.lua`, `strategy-executor.lua`, `policy-rescue.lua`, and `policy-orchestrator.lua`.
4. `policy_orchestrator` chooses the active candidate from profile/domain state and executes its step list through `strategy-executor`.
5. Runtime fallback for these profiles is expected to happen inside `policy_orchestrator`; do not wire an additional standalone `policy_rescue` block for the same profile unless you explicitly want a second independent pass.

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
- `lua/policy-state.lua`: loads and caches `runtime_snapshot.lua` for policy runtime.
- `lua/step-library.lua`: adapter layer that maps policy candidate steps onto builtin `nfqws` Lua handlers.
- `lua/strategy-executor.lua`: constraint checks and ordered step execution for policy candidates.
- `lua/policy-rescue.lua`: fallback chain used by `policy_orchestrator` when no usable candidate is available.
- `lua/policy-orchestrator.lua`: runtime entrypoint for builder policy profiles; selects active candidate, executes it, and signals revalidation on runtime failures.
- `webui/app.js`: browser control plane. Now includes embedded builder panels for supported profiles, async discovery polling, and candidate apply actions.
- `webui/styles.css`: WebUI layout and builder-specific responsive fixes. Builder discovery panels now also expose recommendation and validator quality badges for manual testing.
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
- Builder/discovery also persists candidate metadata used by discovery ranking and pruning. Current candidate `.env` / knowledge fields include `CAPABILITIES`, `REQUIRES`, `FEATURES`, `RISK_FLAGS`, `COST_SCORE`, `STABILITY_HINT`, and `DIVERSITY_KEY`.
- Family scan is now internally tiered inside the existing `family_scan` phase. The external phase contract stays `cached -> family_scan -> optimize -> validate`, but shell discovery runs internal groups in order:
  - `cheap_basics`
  - `split_core`
  - `fake_core`
  - `combos`
  - `expensive_edge`

Current discovery remains shell-owned. There is no standalone Lua decision engine for discovery. Ranking, pruning, feature-aware optimize generation, and knowledge replay must remain executable in plain shell on the router.

Important practical consequence:

- many changes that look "config-only" also affect shell menu actions
- many changes that look "shell-only" are actually constrained by Lua profile numbering and `strategy=N` semantics
- builder changes affect shell menus, CGI response contracts, WebUI rendering, and config-numbering assumptions at the same time
- discovery ranking and optimize behavior now also depend on builder metadata persistence. If you change the metadata schema, update writer and reader paths together.
- Discovery ranking also depends on validator quality fields propagated through `builder_probe_target()` and stored in session results: `dns_state`, `baseline_state`, `tls12_ok`, `tls13_ok`, `long_get_ok`, `failure_class`, `confidence`, `transport_ok`.
- Policy runtime correctness depends on filesystem permissions too: `runtime_snapshot.lua` must be readable by the user that runs `nfqws2` (`--user=nobody` in current OpenWRT installs). If the snapshot is written with mode `0600`, `policy_orchestrator` silently falls back to rescue.
- `policy-state.lua` caches the loaded snapshot in Lua (`POLICY_SNAPSHOT_TTL` is currently `3` seconds). Any validator or test harness that rewrites runtime state and probes immediately can accidentally test the previously active candidate.
- Builder candidate step serialization must preserve Lua value types expected by builtin handlers. In particular, `multisplit`/related `pos` values that look numeric still need to remain strings (`"2"`, not `2`).
- `step-library.lua` must include handlers for every operation that builder can emit. At minimum this includes `tcpseg`, `oob`, `syndata`, `fake`, `multisplit`, `fakeddisorder`, `fakedsplit`, `hostfakesplit`, `multidisorder`, `udplen`, and `send`.
- The menu test (`01`) and discovery validator are separate code paths. They currently use different timeout budgets, so “works in discovery” and “passes menu check” are not equivalent unless you align those settings deliberately.

## High-Risk Areas

- `config.default` is structurally coupled to shell code. Menu actions and strategy helpers depend on exact markers, profile ordering, and recognizable patterns such as `--lua-desync=...strategy=N`.
- `lib/actions.sh` uses targeted `sed`/`awk` replacements against `/opt/zapret2/config`. Small wording changes in config blocks can silently break toggles.
- `lib/strategies.sh` derives max strategy counts from config content. If profile structure changes, strategy menus can go out of sync.
- `lib/strategy_builder.sh` patches live config by inserting generated blocks marked with `# Z2R_BUILDER_BEGIN profile=N` / `# Z2R_BUILDER_END profile=N`. Any change to profile boundaries, numbering rules, or `NFQWS2_OPT` structure can break builder apply/discovery.
- `lib/strategy_builder.sh` also compiles the policy catalog Lua used by runtime. A bad serialization change here can make a candidate look valid in metadata but fail only at execution time inside `nfqws`.
- `z2r.sh` performs destructive operations on target machines, including removing or rebuilding `/opt/zapret2`.
- `orchestra/orchestrator.sh` assumes specific log patterns and state file locations. Renaming emitted messages or moving paths can break learning/locking.
- `lua/strategy-lock-manager.lua` is a shared source of truth for hostname normalization and lock/block state. Duplicating normalization elsewhere is likely to cause subtle bugs.
- Builder profile `1` is mixed `tls/http`, so any code that applies a generated strategy must keep both lock rows aligned; otherwise runtime behavior diverges by protocol.
- WebUI discovery is asynchronous and stateful. `webui/cgi-bin/_lib.sh` now relies on PID/state/log files under `/opt/zapret2/extra_strats/cache/webui-builder`; changing these paths or response shapes can break progress tracking.
- Builder WebUI consumes `last_session.results` and `recommended_candidate` directly from discovery session JSON. New fields should be added additively; keep `candidate`, `label`, `result`, `score`, and `elapsed_ms` stable.
- Builder CGI should prefer runtime/cache files under `/opt/zapret2/extra_strats/cache/webui-builder` over calling heavy builder functions on request. The intended model is: discovery writes progress/results, builder writes candidate caches, CGI mostly serves files.
- Discovery optimization is now two-layered: feature-aware generation tries to preserve successful anchor traits first, then falls back to static family optimizations. If `FEATURES` parsing regresses, discovery still works but optimize quality degrades.
- Knowledge replay uses a TSV cache with signature-based deduplication. If you add, remove, or reorder columns, update both `builder_generate_cached_candidates()` and `builder_record_knowledge_entry()` in lockstep.
- Internal family-scan tiers must not leak into the external session phase list unless CGI/WebUI contracts are updated too. If you need more granularity, keep it inside shell orchestration first.
- Validator result JSON is now part of the discovery quality model. Add new quality fields additively and keep legacy top-level fields (`verdict`, `score`, `elapsed_ms`) stable for WebUI and shell readers.
- `runtime_snapshot.lua`, `runtime_snapshot.last_good.lua`, and per-profile catalog Lua are live runtime inputs now. If you repair generated candidate types or step definitions, verify both the source generator and the already-generated deployed files.
- Temporary workaround currently in use: validator sleeps after rewriting runtime state so `policy-state.lua` cache can expire before probe traffic starts. This should be replaced later with a more correct cache-busting or explicit reload mechanism.

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
- If you edit candidate metadata helpers, also inspect `lib/discovery_engine.sh`; ranking, diversity-aware validation promotion, and feature-aware optimize fallback depend on those fields.
- Prefer extending existing family/feature maps over adding more ad-hoc label regexes. Candidate metadata is now the intended hook for richer discovery decisions.
- If you edit validator result shape or `builder_probe_target()`, also inspect `lib/discovery_engine.sh`, `builder_ranked_results()`, and WebUI readers. The current system expects additive quality fields, not replacement of legacy ones.
- If you edit WebUI polling, avoid overlapping requests during discovery. The router is CPU-constrained; prefer one in-flight refresh at a time and keep `builder-candidates.cgi` off the hot path while discovery is running.

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
- `lib/discovery_engine.sh`
- `webui/cgi-bin/_lib.sh`
- `webui/app.js`
- `webui/styles.css`
- deployed builder knowledge TSV under `/opt/zapret2/extra_strats/cache/builder/.../knowledge.tsv` if the issue involves cached replay, recommendation drift, or missing candidate metadata

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
- if candidate metadata or ranking changed, verify candidate `.env` persistence, knowledge TSV replay, and that discovery still emits valid `results` / `ranking` JSON
- if optimize generation changed, verify both feature-aware generation and fallback static family generation
- if family-scan ordering changed, verify internal tier gating still preserves the external `family_scan` phase contract
- if validator quality fields changed, verify `builder_probe_target()` propagation, `results` / `recommended_candidate` JSON shape, and that builder CLI/WebUI still parse ranking lines
- if WebUI builder flow changed, verify that `builder-candidates.cgi` can answer from cache only, `discovery-results.cgi` shows runtime progress while discovery is running, and stop/cancel still leaves a readable final state
- if validator/runtime-state interaction changed, verify both paths: discovery validator results and menu item `01` (`lib/netcheck.sh`) because they are separate implementations with separate timeout assumptions
- if policy runtime changed, verify all of: snapshot permissions, active candidate in profile/domain state, `runtime_snapshot.lua` contents, and actual `nfqws2` syslog lines for `policy_orchestrator`

## Local Inspection Notes

- The repository content is largely Russian UTF-8 text. On Windows PowerShell it may display as mojibake if the console encoding is not UTF-8.
- This workspace is the source repository, not the deployed `/opt/zapret2` tree. Edit source files here unless you are intentionally debugging a live deployment copy.
