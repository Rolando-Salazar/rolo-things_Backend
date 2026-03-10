-- Reparando Trigger de Perfiles (Para que el id no dé error de ForeignKey en tasks)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, email)
  VALUES (new.id, new.email);
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Insertar cualquier usuario que se haya creado manualmente y haya quedado sin perfil
INSERT INTO public.profiles (id, email)
SELECT id, email FROM auth.users WHERE id NOT IN (SELECT id FROM public.profiles);

-- Reparar la Referencia Circular (Bucle Infinito en RLS)
DROP POLICY IF EXISTS "Collaborators can view projects" ON projects;
DROP POLICY IF EXISTS "View project collaborators" ON collaborators;
DROP POLICY IF EXISTS "Users view tasks" ON tasks;
DROP POLICY IF EXISTS "Users update tasks" ON tasks;

CREATE OR REPLACE FUNCTION public.is_collaborator_on_project(check_project_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM collaborators c WHERE c.project_id = check_project_id AND c.user_id = auth.uid()
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.is_project_owner(check_project_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM projects p WHERE p.id = check_project_id AND p.owner_id = auth.uid()
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Nuevas reglas limpias sin bucles
CREATE POLICY "Collaborators can view projects" ON projects FOR SELECT USING (is_collaborator_on_project(id));
CREATE POLICY "View project collaborators" ON collaborators FOR SELECT USING (user_id = auth.uid() OR is_project_owner(project_id));
CREATE POLICY "Users view tasks" ON tasks FOR SELECT USING (auth.uid() = owner_id OR is_collaborator_on_project(project_id) OR assigned_to = auth.uid());
CREATE POLICY "Users update tasks" ON tasks FOR UPDATE USING (auth.uid() = owner_id OR is_collaborator_on_project(project_id) OR assigned_to = auth.uid());

-- Asegurar Permisos de API para evitar 500 o fallos de lectura en supabase-js
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL ROUTINES IN SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;
