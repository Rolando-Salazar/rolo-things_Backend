import { Client } from 'pg';

async function fixPolicy() {
    const client = new Client({
        connectionString: 'postgresql://postgres:Rolillo1991.@db.vlyydgzxefbqubjnrsof.supabase.co:5432/postgres',
        ssl: { rejectUnauthorized: false }
    });

    try {
        await client.connect();

        // Disable conflicting policies causing the recursion 
        await client.query(`DROP POLICY IF EXISTS "Collaborators can view and edit" ON collaborators;`);

        // Recreate it without recursion (direct check instead of nesting queries inside same table)
        await client.query(`
            CREATE OR REPLACE FUNCTION is_project_member(check_project_id UUID)
            RETURNS BOOLEAN AS $$
            BEGIN
                RETURN EXISTS (
                    SELECT 1 
                    FROM projects p
                    LEFT JOIN collaborators c ON p.id = c.project_id
                    WHERE p.id = check_project_id 
                    AND (p.owner_id = auth.uid() OR c.user_id = auth.uid())
                );
            END;
            $$ LANGUAGE plpgsql SECURITY DEFINER;
        `);
        console.log('Fixed collaborator policy successfully.');

        // Verify task RLS has no infinite recursion
        await client.query(`DROP POLICY IF EXISTS "Users can view assigned and collaborated tasks" ON tasks;`);
        await client.query(`
            CREATE POLICY "Users can view assigned and collaborated tasks"
            ON tasks FOR SELECT
            USING (
                owner_id = auth.uid() 
                OR assigned_to = auth.uid()
                OR (project_id IS NOT NULL AND is_project_member(project_id))
            );
        `);
        console.log('Fixed tasks policy successfully.');

        console.log('Done!');
    } catch (e) {
        console.error(e);
    } finally {
        await client.end();
    }
}

fixPolicy();
