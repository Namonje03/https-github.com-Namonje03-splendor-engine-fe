-- Create profiles table
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT NOT NULL,
  phone_number TEXT,
  avatar_url TEXT,
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Create chilimba_groups table
CREATE TABLE public.chilimba_groups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  admin_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  contribution_amount DECIMAL(10,2) NOT NULL,
  frequency TEXT NOT NULL CHECK (frequency IN ('weekly', 'bi-weekly', 'monthly')),
  start_date DATE NOT NULL,
  max_members INTEGER NOT NULL DEFAULT 10,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'paused')),
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Create group_members table
CREATE TABLE public.group_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID REFERENCES public.chilimba_groups(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  join_date TIMESTAMPTZ DEFAULT now() NOT NULL,
  position INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'completed')),
  UNIQUE(group_id, user_id),
  UNIQUE(group_id, position)
);

-- Create contributions table
CREATE TABLE public.contributions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID REFERENCES public.chilimba_groups(id) ON DELETE CASCADE NOT NULL,
  member_id UUID REFERENCES public.group_members(id) ON DELETE CASCADE NOT NULL,
  amount DECIMAL(10,2) NOT NULL,
  contribution_date TIMESTAMPTZ DEFAULT now() NOT NULL,
  cycle_number INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'failed')),
  payment_method TEXT,
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Create payouts table
CREATE TABLE public.payouts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID REFERENCES public.chilimba_groups(id) ON DELETE CASCADE NOT NULL,
  recipient_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  amount DECIMAL(10,2) NOT NULL,
  cycle_number INTEGER NOT NULL,
  scheduled_date DATE NOT NULL,
  actual_date TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'completed', 'failed')),
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Enable Row Level Security
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chilimba_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contributions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payouts ENABLE ROW LEVEL SECURITY;

-- Profiles policies
CREATE POLICY "Users can view all profiles"
  ON public.profiles FOR SELECT
  USING (true);

CREATE POLICY "Users can update own profile"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

-- Chilimba groups policies
CREATE POLICY "Anyone can view active groups"
  ON public.chilimba_groups FOR SELECT
  USING (true);

CREATE POLICY "Authenticated users can create groups"
  ON public.chilimba_groups FOR INSERT
  WITH CHECK (auth.uid() = admin_id);

CREATE POLICY "Admins can update their groups"
  ON public.chilimba_groups FOR UPDATE
  USING (auth.uid() = admin_id);

-- Group members policies
CREATE POLICY "Members can view their group memberships"
  ON public.group_members FOR SELECT
  USING (auth.uid() = user_id OR 
         auth.uid() IN (SELECT admin_id FROM chilimba_groups WHERE id = group_id));

CREATE POLICY "Users can join groups"
  ON public.group_members FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can manage group members"
  ON public.group_members FOR UPDATE
  USING (auth.uid() IN (SELECT admin_id FROM chilimba_groups WHERE id = group_id));

-- Contributions policies
CREATE POLICY "Members can view group contributions"
  ON public.contributions FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM group_members 
    WHERE group_members.group_id = contributions.group_id 
    AND group_members.user_id = auth.uid()
  ));

CREATE POLICY "Members can create contributions"
  ON public.contributions FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM group_members 
    WHERE group_members.id = member_id 
    AND group_members.user_id = auth.uid()
  ));

-- Payouts policies
CREATE POLICY "Members can view group payouts"
  ON public.payouts FOR SELECT
  USING (auth.uid() = recipient_id OR 
         EXISTS (
           SELECT 1 FROM group_members 
           WHERE group_members.group_id = payouts.group_id 
           AND group_members.user_id = auth.uid()
         ));

-- Create function to handle profile creation
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', 'User'));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to create profile on user signup
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Create function to update updated_at timestamp
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Add triggers for updated_at
CREATE TRIGGER update_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER update_chilimba_groups_updated_at
  BEFORE UPDATE ON public.chilimba_groups
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();