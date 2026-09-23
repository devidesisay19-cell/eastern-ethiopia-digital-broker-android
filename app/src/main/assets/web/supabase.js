/* Eastern Ethiopia General Digital Broker - Shared Supabase client */
const SUPABASE_URL = "https://ubkfrpkapqnlaiscrxim.supabase.co";
const SUPABASE_KEY = "sb_publishable_5EokG_AyxU4BvcMiq1zyqg_B-NIMoeE";
let db = null;
let supabaseClient = null;
function initializeSupabase() {
    if (!window.supabase) {
        console.error("Supabase JavaScript library was not loaded.");
        return false;
    }
    try {
        db = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
        supabaseClient = db;
        console.log("SUPABASE CLIENT CREATED SUCCESSFULLY");
        return true;
    } catch (error) {
        console.error("SUPABASE INITIALIZATION ERROR:", error);
        db = null;
        supabaseClient = null;
        return false;
    }
}
initializeSupabase();
