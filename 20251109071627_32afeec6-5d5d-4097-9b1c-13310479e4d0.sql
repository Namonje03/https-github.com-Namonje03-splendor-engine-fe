-- Create group_invitations table
CREATE TABLE public.group_invitations (
  id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  group_id uuid NOT NULL REFERENCES public.chilimba_groups(id) ON DELETE CASCADE,
  invited_by uuid NOT NULL,
  email text,
  phone_number text,
  token text NOT NULL UNIQUE,
  status text NOT NULL DEFAULT 'pending',
  expires_at timestamp with time zone NOT NULL,
  accepted_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT check_contact_info CHECK (email IS NOT NULL OR phone_number IS NOT NULL)
);

-- Enable RLS
ALTER TABLE public.group_invitations ENABLE ROW LEVEL SECURITY;

-- Admins can create invitations for their groups
CREATE POLICY "Admins can create invitations"
ON public.group_invitations
FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.chilimba_groups
    WHERE chilimba_groups.id = group_invitations.group_id
    AND chilimba_groups.admin_id = auth.uid()
  )
);

-- Admins can view invitations for their groups
CREATE POLICY "Admins can view group invitations"
ON public.group_invitations
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.chilimba_groups
    WHERE chilimba_groups.id = group_invitations.group_id
    AND chilimba_groups.admin_id = auth.uid()
  )
);

-- Anyone can view their own invitation by token (for public acceptance page)
CREATE POLICY "Anyone can view invitation by token"
ON public.group_invitations
FOR SELECT
USING (true);

-- System can update invitation status
CREATE POLICY "System can update invitations"
ON public.group_invitations
FOR UPDATE
USING (true);