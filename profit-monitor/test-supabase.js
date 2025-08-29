// Test Supabase connection
import { createClient } from '@supabase/supabase-js';

// ใส่ค่าจริงตรงนี้
const supabaseUrl = 'https://YOUR_PROJECT_ID.supabase.co';
const supabaseKey = 'YOUR_ANON_KEY';

const supabase = createClient(supabaseUrl, supabaseKey);

async function testConnection() {
    try {
        console.log('Testing Supabase connection...');
        console.log('URL:', supabaseUrl);
        console.log('Key:', supabaseKey.substring(0, 20) + '...');
        
        // Test simple query
        const { data, error } = await supabase
            .from('settings')
            .select('*')
            .limit(1);
            
        if (error) {
            console.error('❌ Connection failed:', error.message);
        } else {
            console.log('✅ Connection successful!');
            console.log('Data:', data);
        }
    } catch (err) {
        console.error('❌ Error:', err.message);
    }
}

testConnection();
