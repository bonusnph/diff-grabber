import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { storage } from '$lib/storage-supabase.js';

export const DELETE: RequestHandler = async () => {
	try {
		await storage.clearData();
		
		return json({ 
			status: 'success',
			message: 'All account data cleared successfully'
		});
		
	} catch (error) {
		console.error('Error clearing account data:', error);
		return json({ error: 'Failed to clear account data' }, { status: 500 });
	}
};
