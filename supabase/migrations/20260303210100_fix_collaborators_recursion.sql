-- 1. Eliminamos las reglas que causaban el bucle infinito de seguridad
DROP POLICY IF EXISTS "Collaborators can view and edit" ON collaborators;
DROP POLICY IF EXISTS "Users can view assigned and collaborated tasks" ON tasks;

-- 2. Creamos una función directa para los permisos
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

-- 3. Volvemos a crear la regla de las Tareas de forma segura (sin bucles)
CREATE POLICY "Users can view assigned and collaborated tasks"
ON tasks FOR SELECT
USING (
    owner_id = auth.uid() 
    OR assigned_to = auth.uid()
    OR (project_id IS NOT NULL AND is_project_member(project_id))
);

-- 4. Creamos una regla simple para los colaboradores
CREATE POLICY "Collaborators flat view" 
ON collaborators FOR SELECT 
USING (user_id = auth.uid());
