import type { ExternalWallet } from './types.js';

export const EXTERNAL_WALLET_NAME_MAX = 40;

export function defaultExternalWallet(): ExternalWallet {
	return { name: 'Wallet', balance: 0, updated_at: '' };
}

export function roundMoney(value: number): number {
	return Math.round(value * 100) / 100;
}

export function normalizeExternalWallet(raw: unknown): ExternalWallet {
	const fallback = defaultExternalWallet();
	if (!raw || typeof raw !== 'object') return fallback;
	const value = raw as Record<string, unknown>;
	const name = typeof value.name === 'string' ? value.name.trim().slice(0, EXTERNAL_WALLET_NAME_MAX) : '';
	const balanceRaw = typeof value.balance === 'number' ? value.balance : Number(value.balance);
	const updatedAt = typeof value.updated_at === 'string' ? value.updated_at : '';
	return {
		name: name || fallback.name,
		balance: Number.isFinite(balanceRaw) ? roundMoney(balanceRaw) : 0,
		updated_at: updatedAt
	};
}
