# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Primary user is an FX hedge-desk operator who already runs MT4/MT5 Expert Advisors. They glance this dashboard on a phone, tablet, or desk monitor—often after switching away from another app—to see whether the book is healthy. (Inferred from the existing Profit Monitor surface and the prior session’s resume/mobile brief.)

## Product Purpose

Profit Monitor aggregates live account heartbeats from EAs and shows net P/L across hedge units (paired BUY/SELL legs, often across two brokers). Success is: the operator can read book health and act on WD/DP, snapshots, and unit settings without leaving the page.

## Positioning

The mechanism a generic portfolio dashboard cannot copy: magic-matched hedge pairs across accounts, unit-level capital/warning thresholds, WD/DP notes that adjust displayed P/L, and stale/low-equity/unpaired states from EA timestamps.

## Operating Context

Used alongside MetaTrader terminals. Data arrives via webhook; the page polls. Operators switch apps frequently on mobile and expect the latest book on return. Settings (unit capital, mappings, broker min margin, WD/DP, danger-zone clear) live in one modal.

## Capabilities and Constraints

Confirmed on the current surface and required to remain: hero adjusted P/L and percent; Total P/L / WD / DP; Snapshot Δ; Active / Open Pairs / Low Equity; Positive/Negative pair chips; Collapse/Expand/Filters; every unit field (pairs table, account table, C/T/WD/DP, D/W adjust, Set P/L Zero, Simplify WD/DP); Total tree; empty state; full Settings fieldsets. Visual replacement must not drop fields or settings. Brief pin: new color and presentation so the product no longer looks like the incumbent stone/indigo card stack.

## Brand Commitments

Product title in use: Profit Monitor Dashboard. No separate brand system. Binding request: replace the visual world entirely while keeping every readable and configurable field.

## Evidence on Hand

Live implementation: `profit-monitor-for-docker/src/routes/+page.svelte`. No customer testimonials or marketing claims exist; do not invent any.

## Product Principles

- The book is the product: pair health, equity risk, and freshness outrank chrome.
- Glance first, edit in place: WD/DP and settings stay reachable.
- Every field that exists today remains findable after a visual change.
- Mobile return is a first-class moment: latest data without waiting on a countdown.
- Domain language (unit, magic, lots, pts, WD/DP) stays; presentation may clarify it.

## Accessibility & Inclusion

Pinch-zoom must remain enabled. Touch targets on phone should stay usable. Color cannot be the only status signal.
