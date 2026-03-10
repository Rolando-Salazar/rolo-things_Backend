import { Client } from 'pg';
import * as fs from 'fs';
import * as path from 'path';

async function runSQL() {
    const connectionString = "postgresql://postgres:Rolillo1991@db.bdwevhijvhcsztcwxpjs.supabase.co:5432/postgres";
    const client = new Client({
        connectionString,
        ssl: { rejectUnauthorized: false }
    });

    try {
        await client.connect();
        console.log('Connected to Supabase PostgreSQL database.');

        const schemaPath = path.join(__dirname, 'supabase_schema.sql');
        const sql = fs.readFileSync(schemaPath, 'utf8');

        console.log('Executing schema script...');
        await client.query(sql);

        console.log('Success! Schema created successfully.');
    } catch (err: any) {
        console.error('Error executing script:', err.message);
    } finally {
        await client.end();
    }
}

runSQL();
