import type { AccountSummary, OrderInfo } from '$lib/types.js';
import { isLowEquityWarning } from '$lib/equity-warning-model.js';

export interface PairInfo {
	symbol: string;
	/** Raw symbols from BUY / SELL legs (pair label is derived, sorted A–Z). */
	buySymbol?: string;
	sellSymbol?: string;
	buyAccount: string;
	sellAccount: string;
	buyBroker: string;
	sellBroker: string;
	buyPrice: number;
	sellPrice: number;
	diff: number;
	diffPoints: number;
	lots: number;
	buyLots: number;
	sellLots: number;
	openTime: string;
	/** BUY leg open time (ISO); pair rows only. */
	buyOpenTime?: string;
	/** SELL leg open time (ISO); pair rows only. */
	sellOpenTime?: string;
	pairMagic?: number;
}

export type UnitPair = PairInfo & { unit: number };

export type UnmatchedLeg = OrderInfo & { account_number: string; broker_name: string };

export type UnitPairsResult = { pairs: PairInfo[]; unmatched: UnmatchedLeg[] };

function nearlyEqualAtTick(price: number, roundedToTick: number): boolean {
	return Math.abs(price - roundedToTick) <= 1e-9 * Math.max(1, Math.abs(price));
}

/** Smallest fractional digit count that represents this quote on a uniform grid. */
function inferFractionDecimalsForPrice(p: number): number {
	for (let d = 0; d <= 12; d++) {
		const scale = Math.pow(10, d);
		const r = Math.round(p * scale) / scale;
		if (nearlyEqualAtTick(r, p)) return d;
	}
	return 5;
}

/**
 * Align BUY and SELL to the coarser implied precision (min decimals per leg), scale to integers, subtract.
 * Example: buy 4500.12 (2 dp), sell 4600.120 (3 dp) → scale ×100 → 450012 vs 460012 → diff 10000 ticks at 0.01.
 */
export function spreadDiffWholeTicks(buyPrice: number, sellPrice: number): number {
	const db = inferFractionDecimalsForPrice(buyPrice);
	const ds = inferFractionDecimalsForPrice(sellPrice);
	const d = Math.min(db, ds);
	const scale = Math.pow(10, d);
	return Math.round(sellPrice * scale) - Math.round(buyPrice * scale);
}

/** Both leg symbols, sorted alphabetically, as "A - B" (for cross-broker suffixes). */
export function formatPairSymbolsLabel(buySym: string | undefined, sellSym: string | undefined): string {
	const bs = (buySym ?? '').trim();
	const ss = (sellSym ?? '').trim();
	if (!bs && !ss) return '';
	if (!bs) return ss;
	if (!ss) return bs;
	const [a, b] = [bs, ss].sort((x, y) => x.localeCompare(y));
	return `${a} - ${b}`;
}

export function computeUnitPairs(accounts: AccountSummary[]): UnitPairsResult {
	type Annotated = OrderInfo & { account_number: string; broker_name: string; openMs: number };

	function annotate(acc: AccountSummary, o: OrderInfo): Annotated | null {
		if (!o?.openTime) return null;
		const ms = new Date(o.openTime).getTime();
		if (!isFinite(ms)) return null;
		return {
			...o,
			account_number: acc.account_number,
			broker_name: acc.broker_name,
			openMs: ms
		};
	}

	function orderMagic(o: OrderInfo): number | undefined {
		if (typeof o.magic !== 'number' || !Number.isFinite(o.magic)) return undefined;
		return o.magic;
	}

	function makePair(buy: Annotated, sell: Annotated, magic?: number): PairInfo {
		const diff = sell.price - buy.price;
		const bs = (buy.symbol || '').trim();
		const ss = (sell.symbol || '').trim();
		const pi: PairInfo = {
			symbol: formatPairSymbolsLabel(bs, ss) || bs || ss,
			buySymbol: bs,
			sellSymbol: ss,
			buyAccount: buy.account_number,
			sellAccount: sell.account_number,
			buyBroker: buy.broker_name,
			sellBroker: sell.broker_name,
			buyPrice: buy.price,
			sellPrice: sell.price,
			diff,
			diffPoints: spreadDiffWholeTicks(buy.price, sell.price),
			lots: (buy.lots + sell.lots) / 2,
			buyLots: buy.lots,
			sellLots: sell.lots,
			openTime: new Date(Math.min(buy.openMs, sell.openMs)).toISOString(),
			buyOpenTime: new Date(buy.openMs).toISOString(),
			sellOpenTime: new Date(sell.openMs).toISOString()
		};
		if (magic !== undefined) pi.pairMagic = magic;
		return pi;
	}

	const allBuys: Annotated[] = [];
	const allSells: Annotated[] = [];
	for (const acc of accounts || []) {
		const orders = (acc.orders || []) as OrderInfo[];
		for (const o of orders) {
			const a = annotate(acc, o);
			if (!a) continue;
			if (o.side === 'BUY') allBuys.push(a);
			else if (o.side === 'SELL') allSells.push(a);
		}
	}

	const pairs: PairInfo[] = [];
	const buysMagic = new Map<number, Annotated[]>();
	const sellsMagic = new Map<number, Annotated[]>();
	const unpairedBuys: Annotated[] = [];
	const unpairedSells: Annotated[] = [];

	for (const buy of allBuys) {
		const m = orderMagic(buy);
		if (m !== undefined) {
			const arr = buysMagic.get(m) ?? [];
			arr.push(buy);
			buysMagic.set(m, arr);
		} else {
			unpairedBuys.push(buy);
		}
	}
	for (const sell of allSells) {
		const m = orderMagic(sell);
		if (m !== undefined) {
			const arr = sellsMagic.get(m) ?? [];
			arr.push(sell);
			sellsMagic.set(m, arr);
		} else {
			unpairedSells.push(sell);
		}
	}

	const magicKeys = new Set<number>([...buysMagic.keys(), ...sellsMagic.keys()]);
	for (const mk of magicKeys) {
		const bList = [...(buysMagic.get(mk) ?? [])].sort((x, y) => x.openMs - y.openMs);
		const sList = [...(sellsMagic.get(mk) ?? [])].sort((x, y) => x.openMs - y.openMs);
		const n = Math.min(bList.length, sList.length);
		for (let i = 0; i < n; i++) {
			pairs.push(makePair(bList[i], sList[i], mk));
		}
		for (let i = n; i < bList.length; i++) unpairedBuys.push(bList[i]);
		for (let i = n; i < sList.length; i++) unpairedSells.push(sList[i]);
	}

	unpairedBuys.sort((a, b) => a.openMs - b.openMs);
	unpairedSells.sort((a, b) => a.openMs - b.openMs);

	const unmatched: UnmatchedLeg[] = [];
	for (const leg of unpairedBuys) {
		const { openMs: _omitMs, ...rest } = leg;
		unmatched.push(rest);
	}
	for (const leg of unpairedSells) {
		const { openMs: _omitMs, ...rest } = leg;
		unmatched.push(rest);
	}

	const magicAscKey = (m: number | undefined) =>
		typeof m === 'number' && Number.isFinite(m) ? m : Number.POSITIVE_INFINITY;
	pairs.sort((a, b) => magicAscKey(a.pairMagic) - magicAscKey(b.pairMagic));
	unmatched.sort((a, b) => magicAscKey(orderMagic(a)) - magicAscKey(orderMagic(b)));

	return { pairs, unmatched };
}

export function computeUnitDelta(accounts: AccountSummary[]): number | null {
	const buy = accounts.find(
		(a) => a.lastPositionSide === 'BUY' && (a.lastPositionEntryPrice ?? 0) > 0
	);
	const sell = accounts.find(
		(a) => a.lastPositionSide === 'SELL' && (a.lastPositionEntryPrice ?? 0) > 0
	);
	if (!buy || !sell) return null;
	const buyPrice = buy.lastPositionEntryPrice as number;
	const sellPrice = sell.lastPositionEntryPrice as number;
	return spreadDiffWholeTicks(buyPrice, sellPrice);
}

/** Top-summary legacy pair when unit has no order-json pairing (EA last-position only). */
export function computeLegacyUnitPair(unit: number, accounts: AccountSummary[]): UnitPair | null {
	const buy = accounts.find(
		(a) => a.lastPositionSide === 'BUY' && (a.lastPositionEntryPrice ?? 0) > 0
	);
	const sell = accounts.find(
		(a) => a.lastPositionSide === 'SELL' && (a.lastPositionEntryPrice ?? 0) > 0
	);
	if (!buy || !sell) return null;
	const buyPrice = buy.lastPositionEntryPrice as number;
	const sellPrice = sell.lastPositionEntryPrice as number;
	const diff = sellPrice - buyPrice;
	const buyLots = buy.lastSize ?? 0;
	const sellLots = sell.lastSize ?? 0;
	return {
		unit,
		symbol: '',
		buyAccount: buy.account_number,
		sellAccount: sell.account_number,
		buyBroker: buy.broker_name,
		sellBroker: sell.broker_name,
		buyPrice,
		sellPrice,
		diff,
		diffPoints: spreadDiffWholeTicks(buyPrice, sellPrice),
		lots: (buyLots + sellLots) / 2,
		buyLots,
		sellLots,
		openTime: buy.last_update || sell.last_update,
		buyOpenTime: buy.last_update || undefined,
		sellOpenTime: sell.last_update || undefined
	};
}

export function listDisplayPairs(unitGroups: Record<string, AccountSummary[]> | undefined): UnitPair[] {
	const groups = unitGroups || {};
	const unitPairsMap = Object.entries(groups).reduce(
		(acc, [unitStr, accounts]) => {
			const unit = parseInt(unitStr);
			acc[unit] = computeUnitPairs(accounts);
			return acc;
		},
		{} as Record<number, UnitPairsResult>
	);

	const allPairs = Object.entries(unitPairsMap).flatMap(([unitStr, value]) => {
		const unit = parseInt(unitStr);
		return (value?.pairs || []).map((p) => ({ ...p, unit }));
	});

	const legacyUnitPairs = Object.entries(groups).flatMap(([unitStr, accounts]) => {
		const unit = parseInt(unitStr);
		const ud = unitPairsMap[unit];
		if (!ud || ud.pairs.length > 0 || ud.unmatched.length > 0) return [];
		const lp = computeLegacyUnitPair(unit, accounts);
		return lp ? [lp] : [];
	});

	return [...allPairs, ...legacyUnitPairs];
}

export type UnitDiffLane = { unit: number; diffs: number[]; lowEquity: boolean };

/** One lane per unit, in unit order. Empty diffs means the group has no open pair. */
export function listUnitDiffLanes(
	unitGroups: Record<string, AccountSummary[]> | undefined,
	capitals: Record<number, number> = {},
	warnPcts: Record<number, number> = {}
): UnitDiffLane[] {
	const groups = unitGroups || {};
	const byUnit = new Map<number, number[]>();
	for (const pair of listDisplayPairs(groups)) {
		const diffs = byUnit.get(pair.unit) ?? [];
		diffs.push(Math.round(pair.diffPoints));
		byUnit.set(pair.unit, diffs);
	}
	return Object.keys(groups)
		.map((key) => parseInt(key, 10))
		.filter((unit) => Number.isFinite(unit))
		.sort((a, b) => a - b)
		.map((unit) => {
			const accounts = groups[String(unit)] || [];
			return {
				unit,
				diffs: byUnit.get(unit) ?? [],
				lowEquity: accounts.some((account) =>
					isLowEquityWarning(account.latest_equity, capitals[unit] ?? 0, warnPcts[unit])
				)
			};
		});
}

export function splitSignedPairs(pairs: UnitPair[]): { positive: UnitPair[]; negative: UnitPair[] } {
	return {
		positive: pairs.filter((p) => p.diffPoints >= 0).sort((a, b) => b.diffPoints - a.diffPoints),
		negative: pairs.filter((p) => p.diffPoints < 0).sort((a, b) => b.diffPoints - a.diffPoints)
	};
}
