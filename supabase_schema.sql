-- Rolo-Things Database Schema for Supabase
-- This script creates the complete functional structure for the app.

-- Enable UUID extension just in case (Supabase usually has it enabled)
create extension if not exists "uuid-ossp";

-- 1. PROFILES Table (Extends Supabase Auth Auth.users)
create table public.profiles (
    id uuid references auth.users (id) on delete cascade primary key,
    email text unique not null,
    full_name text,
    avatar_url text,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Note: RLS (Row Level Security) policies should be added, but for testing
-- we'll assume basic permissions or disable RLS initially, but it's better to implement it.
alter table public.profiles enable row level security;
create policy "Users can view their own profile." on profiles for select using (auth.uid() = id);
create policy "Users can update their own profile." on profiles for update using (auth.uid() = id);

-- 2. PROJECTS Table
create table public.projects (
    id uuid default uuid_generate_v4() primary key,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    title text not null,
    description text,
    color text, -- For custom project colors
    icon text,  -- Emoji or icon name
    is_archived boolean default false,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.projects enable row level security;
-- Owner policies
create policy "Users view their own projects" on projects for select using (auth.uid() = owner_id);
create policy "Users create their own projects" on projects for insert with check (auth.uid() = owner_id);
create policy "Users update own projects" on projects for update using (auth.uid() = owner_id);
create policy "Users delete own projects" on projects for delete using (auth.uid() = owner_id);

-- 3. COLLABORATORS Table (For sharing projects)
create table public.collaborators (
    user_id uuid references public.profiles(id) on delete cascade,
    project_id uuid references public.projects(id) on delete cascade,
    role text check (role in ('viewer', 'editor')) default 'editor',
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    primary key (user_id, project_id)
);

alter table public.collaborators enable row level security;
-- Add policies to let collaborators view projects
create policy "Collaborators can view projects" on projects for select using (
    exists (select 1 from collaborators where project_id = projects.id and user_id = auth.uid())
);
-- Collaborator permissions policy to view collaborators
create policy "View project collaborators" on collaborators for select using (
    user_id = auth.uid() or 
    exists (select 1 from projects where id = project_id and owner_id = auth.uid())
);

-- 4. TASKS Table
create table public.tasks (
    id uuid default uuid_generate_v4() primary key,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    project_id uuid references public.projects(id) on delete set null,
    title text not null,
    notes text,
    is_completed boolean default false,
    -- Important dates for "Today", "Upcoming", etc.
    start_date date, -- When task shows up in "Today"
    due_date date,   -- Deadline
    completed_at timestamp with time zone,
    -- Assignment
    assigned_to uuid references public.profiles(id) on delete set null,
    priority smallint default 0, -- 0 normal, 1 high, etc.
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.tasks enable row level security;
-- Users can manage tasks they own or tasks in projects they collaborate on
create policy "Users view tasks" on tasks for select using (
    auth.uid() = owner_id or 
    exists (select 1 from collaborators where project_id = tasks.project_id and user_id = auth.uid()) or
    assigned_to = auth.uid()
);
create policy "Users insert tasks" on tasks for insert with check (
    auth.uid() = owner_id
);
create policy "Users update tasks" on tasks for update using (
    auth.uid() = owner_id or 
    exists (select 1 from collaborators where project_id = tasks.project_id and user_id = auth.uid() and role = 'editor') or
    assigned_to = auth.uid()
);
create policy "Users delete tasks" on tasks for delete using (
    auth.uid() = owner_id
);

-- 5. TAGS Table
create table public.tags (
    id uuid default uuid_generate_v4() primary key,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    name text not null,
    color text default '#888888',
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);
alter table public.tags enable row level security;
create policy "View tags" on tags for select using (auth.uid() = owner_id);
create policy "Manage tags" on tags for all using (auth.uid() = owner_id);

-- 6. TASK_TAGS (Many-to-many mapping)
create table public.task_tags (
    task_id uuid references public.tasks(id) on delete cascade,
    tag_id uuid references public.tags(id) on delete cascade,
    primary key (task_id, tag_id)
);
alter table public.task_tags enable row level security;
create policy "View task tags" on task_tags for select using (
    exists (select 1 from tasks where id = task_id and owner_id = auth.uid())
);
create policy "Manage task tags" on task_tags for all using (
    exists (select 1 from tasks where id = task_id and owner_id = auth.uid())
);

-- Optional: Function to update "updated_at" columns automatically
create or replace function update_modified_column()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language 'plpgsql';

create trigger update_profiles_modtime
    before update on profiles
    for each row execute procedure update_modified_column();

create trigger update_projects_modtime
    before update on projects
    for each row execute procedure update_modified_column();

create trigger update_tasks_modtime
    before update on tasks
    for each row execute procedure update_modified_column();

-- Analytics Helper View: Completed Tasks per Day for the last 30 days
create or replace view public.analytics_completed_tasks_daily as
select 
    owner_id, 
    date(completed_at) as date, 
    count(*) as count
from public.tasks
where is_completed = true and completed_at is not null
group by owner_id, date(completed_at);

-- This schema provides everything needed for:
-- Inbox (project_id null)
-- Today (start_date <= today or due_date <= today)
-- Upcoming (start_date > today)
-- Projects (projects table)
-- Analytics (analytics_completed_tasks_daily or query completed_at)
-- Collaboration (collaborators table + assigned_to)
