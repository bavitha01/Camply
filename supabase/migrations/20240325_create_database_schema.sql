-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- Create colleges table
create table public.colleges (
  college_id uuid primary key default uuid_generate_v4(),
  name varchar not null,
  city varchar,
  state varchar,
  university_name varchar,
  college_icon text,
  college_website_url text,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Users table
create table public.users (
  user_id uuid references auth.users primary key,
  name varchar not null,
  email varchar not null,
  phone_number varchar,
  profile_photo_url text,
  academic_id uuid,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Academic details table
create table public.user_academic_details (
  academic_id uuid primary key default uuid_generate_v4(),
  user_id uuid references public.users not null,
  college_id uuid references public.colleges,
  department_name varchar not null,
  branch_name varchar not null,
  admission_year integer not null,
  graduation_year integer not null,
  roll_number varchar not null,
  latest_semester_id uuid,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Semesters table
create table public.semesters (
  semester_id uuid primary key default uuid_generate_v4(),
  academic_id uuid references public.user_academic_details not null,
  semester_number integer not null,
  time_table_url text,
  number_of_ias integer,
  sem_end_marksheet_url text,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Courses table
create table public.courses (
  course_id uuid primary key default uuid_generate_v4(),
  semester_id uuid references public.semesters not null,
  course_name varchar not null,
  syllabus_url text,
  credits integer,
  unit_notes jsonb,
  important_question_papers jsonb,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Campus AI Content table
create table public.campus_ai_content (
  campus_content_id uuid primary key default uuid_generate_v4(),
  college_id uuid references public.colleges not null,
  college_overview_content jsonb,
  facilities_content jsonb,
  placements_content jsonb,
  departments_content jsonb,
  admissions_content jsonb,
  generated_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null,
  content_version integer default 1,
  is_active boolean default true
);

-- User Handbooks table for handbook upload and processing system
create table public.user_handbooks (
  handbook_id uuid primary key default uuid_generate_v4(),
  user_id uuid references public.users not null,
  academic_id uuid references public.user_academic_details not null,

  -- Storage info
  storage_path text not null,
  original_filename varchar not null,
  file_size_bytes bigint,

  -- Processing status
  processing_status varchar default 'uploaded' check (processing_status in ('uploaded', 'processing', 'completed', 'failed')),
  upload_date timestamp with time zone default timezone('utc'::text, now()) not null,
  processed_date timestamp with time zone,
  processing_started_at timestamp with time zone,
  error_message text,

  -- Structured JSON Data (extracted from handbook)
  basic_info jsonb,
  semester_structure jsonb,
  examination_rules jsonb,
  evaluation_criteria jsonb,
  attendance_policies jsonb,
  academic_calendar jsonb,
  course_details jsonb,
  assessment_methods jsonb,
  disciplinary_rules jsonb,
  graduation_requirements jsonb,
  fee_structure jsonb,
  facilities_rules jsonb,

  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Create handbooks storage bucket (for handbook file storage)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) 
values (
  'handbooks', 
  'handbooks', 
  false, 
  104857600, -- 100MB limit
  array['application/pdf']
);

-- Enable RLS
alter table public.users enable row level security;
alter table public.user_academic_details enable row level security;
alter table public.semesters enable row level security;
alter table public.courses enable row level security;
alter table public.colleges enable row level security;
alter table public.campus_ai_content enable row level security;
alter table public.user_handbooks enable row level security;

-- Policies for users
create policy "Users can view own data" on public.users
  for select using (auth.uid() = user_id);
create policy "Users can update own data" on public.users
  for update using (auth.uid() = user_id);
create policy "Users can insert own data" on public.users
  for insert with check (auth.uid() = user_id);

-- Policies for academic details
create policy "Users can view own academic details" on public.user_academic_details
  for select using (user_id = auth.uid());
create policy "Users can update own academic details" on public.user_academic_details
  for update using (user_id = auth.uid());
create policy "Users can insert own academic details" on public.user_academic_details
  for insert with check (user_id = auth.uid());

-- Semester policies
create policy "Users can view own semesters" on public.semesters
  for select using (
    exists (
      select 1 from public.user_academic_details
      where academic_id = semesters.academic_id
      and user_id = auth.uid()
    )
  );
create policy "Users can update own semesters" on public.semesters
  for update using (
    exists (
      select 1 from public.user_academic_details
      where academic_id = semesters.academic_id
      and user_id = auth.uid()
    )
  );
create policy "Users can insert own semesters" on public.semesters
  for insert with check (
    exists (
      select 1 from public.user_academic_details
      where academic_id = semesters.academic_id
      and user_id = auth.uid()
    )
  );

-- Course policies
create policy "Users can view own courses" on public.courses
  for select using (
    exists (
      select 1 from public.semesters s
      join public.user_academic_details uad on s.academic_id = uad.academic_id
      where s.semester_id = courses.semester_id
      and uad.user_id = auth.uid()
    )
  );
create policy "Users can update own courses" on public.courses
  for update using (
    exists (
      select 1 from public.semesters s
      join public.user_academic_details uad on s.academic_id = uad.academic_id
      where s.semester_id = courses.semester_id
      and uad.user_id = auth.uid()
    )
  );
create policy "Users can insert own courses" on public.courses
  for insert with check (
    exists (
      select 1 from public.semesters s
      join public.user_academic_details uad on s.academic_id = uad.academic_id
      where s.semester_id = courses.semester_id
      and uad.user_id = auth.uid()
    )
  );

-- Colleges can be read by all
create policy "Anyone can view colleges" on public.colleges
  for select using (true);

-- Campus AI content can be read by all (shared across users from same college)
create policy "Anyone can view campus AI content" on public.campus_ai_content
  for select using (true);

-- Only system can insert/update campus AI content (managed by backend agents)
create policy "System can manage campus AI content" on public.campus_ai_content
  for all using (false);

-- Handbook policies (with TO clause for better performance)
create policy "Users can view own handbooks" on public.user_handbooks
  for select to authenticated using (user_id = auth.uid());
create policy "Users can insert own handbooks" on public.user_handbooks
  for insert to authenticated with check (user_id = auth.uid());
create policy "Users can update own handbooks" on public.user_handbooks
  for update to authenticated using (user_id = auth.uid());
create policy "Users can delete own handbooks" on public.user_handbooks
  for delete to authenticated using (user_id = auth.uid());

-- Storage policies for handbooks bucket (using improved folder structure)
create policy "Users can upload own handbooks" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'handbooks' 
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[2] = auth.uid()::text
  );
create policy "Users can view own handbooks" on storage.objects
  for select to authenticated using (
    bucket_id = 'handbooks' 
    and (storage.foldername(name))[2] = auth.uid()::text
  );
create policy "Users can update own handbooks" on storage.objects
  for update to authenticated using (
    bucket_id = 'handbooks' 
    and (storage.foldername(name))[2] = auth.uid()::text
  );
create policy "Users can delete own handbooks" on storage.objects
  for delete to authenticated using (
    bucket_id = 'handbooks' 
    and (storage.foldername(name))[2] = auth.uid()::text
  );

-- Add foreign key constraints after tables are created
alter table public.users 
  add constraint fk_academic_details 
  foreign key (academic_id) 
  references public.user_academic_details(academic_id);

alter table public.user_academic_details
  add constraint fk_latest_semester
  foreign key (latest_semester_id)
  references public.semesters(semester_id);

-- Add index for faster AI content queries
create index idx_campus_ai_content_college_id on public.campus_ai_content(college_id);
create index idx_campus_ai_content_active on public.campus_ai_content(college_id, is_active) where is_active = true;

-- Add indexes for handbook queries
create index idx_user_handbooks_user_id on public.user_handbooks(user_id);
create index idx_user_handbooks_academic_id on public.user_handbooks(academic_id);    
create index idx_user_handbooks_status on public.user_handbooks(processing_status);
create index idx_user_handbooks_upload_date on public.user_handbooks(upload_date desc);

-- Add trigger to update updated_at timestamp for campus AI content
create or replace function update_updated_at_column()
returns trigger as $$
begin
    new.updated_at = timezone('utc'::text, now());
    return new;
end;
$$ language 'plpgsql';

create trigger update_campus_ai_content_updated_at 
    before update on public.campus_ai_content 
    for each row execute function update_updated_at_column();

-- Add trigger for handbook updated_at timestamp
create trigger update_user_handbooks_updated_at 
    before update on public.user_handbooks 
    for each row execute function update_updated_at_column();

-- Add comment for documentation
comment on table public.user_handbooks is 'Stores uploaded academic handbooks and their processed data';
comment on column public.user_handbooks.processing_status is 'Status: uploaded, processing, completed, failed';
comment on column public.user_handbooks.storage_path is 'Path in Supabase Storage handbooks bucket'; 