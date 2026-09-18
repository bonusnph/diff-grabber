<script lang="ts">
	import type { DisplayCurrency } from './types.js';

	let { currency, size = 22 }: { currency: DisplayCurrency; size?: number } = $props();

	const height = Math.round(size * 0.72);
</script>

<span
	class="inline-flex overflow-hidden rounded-[2px] border border-[#f5f5f5]/40 shrink-0"
	style="width:{size}px;height:{height}px;"
	title={currency}
	aria-label={currency === 'THB' ? 'Thai Baht' : 'US Dollar'}
	role="img"
>
	{#if currency === 'THB'}
		<svg viewBox="0 0 36 26" width={size} height={height} aria-hidden="true">
			<rect width="36" height="26" fill="#A51931" />
			<rect y="4" width="36" height="18" fill="#F4F5F8" />
			<rect y="9" width="36" height="8" fill="#2D2A4A" />
		</svg>
	{:else}
		<svg viewBox="0 0 36 26" width={size} height={height} aria-hidden="true">
			<rect width="36" height="26" fill="#B22234" />
			<rect y="2" width="36" height="2" fill="#fff" />
			<rect y="6" width="36" height="2" fill="#fff" />
			<rect y="10" width="36" height="2" fill="#fff" />
			<rect y="14" width="36" height="2" fill="#fff" />
			<rect y="18" width="36" height="2" fill="#fff" />
			<rect y="22" width="36" height="2" fill="#fff" />
			<rect width="15" height="14" fill="#3C3B6E" />
		</svg>
	{/if}
</span>
