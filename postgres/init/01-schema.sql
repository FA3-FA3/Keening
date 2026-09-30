-- Keening initial schema. Safe to rerun; later changes belong in migrations.
BEGIN;

-- Internal UUIDs are used for database relations. Firebase UIDs identify users
-- at the API boundary. The API will provision a row on the first authenticated
-- request. Anonymous Firebase users have no email address.
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    firebase_uid TEXT UNIQUE NOT NULL,
    email TEXT,
    username TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- UNIQUE(firebase_uid) already creates the index needed for profile lookup.
COMMIT;
