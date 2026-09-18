---
target: profit-monitor-for-docker dashboard UX
total_score: 19
max_score: 40
na_heuristics: 
p0_count: 1
p1_count: 2
target_identity: "file:/Users/bonusnph/Repositories/viriyawutthikit /diff-grabber/profit-monitor-for-docker/src/routes/+page.svelte"
target_fingerprint: "sha256:d6acad56a997b9f7a32475ab7bd7f5f58a6e09b4884b2fafe262c33218490ccc"
target_path: /Users/bonusnph/Repositories/viriyawutthikit /diff-grabber/profit-monitor-for-docker/src/routes/+page.svelte
timestamp: 2026-09-18T02-25-07Z
slug: profit-monitor-for-docker-src-routes-page-svelte
---
# Critique: Profit Monitor Dashboard (+page.svelte)

Mode: Operate. Target: profit-monitor-for-docker/src/routes/+page.svelte

## Heuristics

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 2 | Countdown and last-update exist; fetch failures are console-only; Settings pauses polling while header still ticks |
| 2 | Match System / Real World | 3 | Desk dialect (WD/DP/lots/pts/magic) is fluent; D/W means three things; EN UI + th-TH numbers |
| 3 | User Control and Freedom | 2 | Collapse/Filters/Cancel exist; WD/DP and Set P/L Zero persist immediately with no undo |
| 4 | Consistency and Standards | 2 | Immediate-save vs Save+reload; status is ~ / ✓ and colored dots; delete modal light-on-dark |
| 5 | Error Prevention | 2 | Fat-finger WD/DP w-20 inputs; user-scalable=no; remove-unit has no confirm |
| 6 | Recognition Rather Than Recall | 2 | Hero chips show only +pts; C/T/D/W/WD/DP unexplained; Settings/Refresh icon-only |
| 7 | Flexibility and Efficiency | 2 | Batch actions exist; no shortcuts; chips not navigational; units default collapsed |
| 8 | Aesthetic and Minimalist Design | 2 | Strong hero number; then equal-weight stone cards, chip walls, 8/9-col tables |
| 9 | Error Recovery | 1 | Almost no user-facing errors; WD/DP optimistic before request |
| 10 | Help and Documentation | 1 | Hover titles only; no glossary |
| **Total** | | **19/40** | **Poor** |

## Design Specificity

LLM: Functionally authored (units, magic pairs, WD/DP, Snapshot Δ). Visually interchangeable dark admin chrome (stone/indigo/emerald).

Deterministic scan: 3 warnings (side-tab L1609; gray-on-color L2554, L2617). Layout-scope: 0. Two gray-on-color hits are false positives (disabled: variants). side-tab is an intentional live-trading accent.

Visual overlays: none. Browser visualization skipped (no automation; no local server started).

## Cognitive load

7/8 checklist failures (only Grouping passed). High / critical.

## Priority Issues

[P0] Live status can lie — Settings pauses fetch; fetch fail is silent; resume used to wait on a frozen 10s countdown.
[P1] Desktop layout welded on; zoom locked — grid-cols-3/2 always; overflow-x tables; Settings max-w-7xl; maximum-scale=1.
[P1] Pair chips are anonymous decoration — +pts only; unit/symbol/lots in title.
[P2] Letter collision C/T/D/W/WD/DP/Adjust.
[P2] Settings is a max-w-7xl kitchen sink with mixed save models.

## Personas

Alex: no shortcuts, collapsed units, chips not jump links.
Casey: top-bar controls, tiny tap targets, horizontal-scroll money fields, zoom locked.
Trader-on-the-go: adjusted P/L can hide a bleeding unit; Partial Data unexplained; units collapsed hide unpaired/stale.

## Questions considered

Actionable-units-first? Snapshot as session ritual? Keep feed live in Settings? Default expand vs collapse?
