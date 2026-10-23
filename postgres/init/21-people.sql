BEGIN;
-- People: friend requests and friendships between users, and the messages
-- friends send each other.
--
-- A request goes from one user to another until it is accepted (it becomes a
-- friendship), declined or cancelled (it is deleted). A friendship is stored
-- once per pair, with the smaller id first.
CREATE TABLE IF NOT EXISTS public.friend_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  recipient_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (sender_id <> recipient_id),
  UNIQUE (sender_id, recipient_id)
);
CREATE INDEX IF NOT EXISTS friend_requests_recipient ON public.friend_requests(recipient_id, created_at);

CREATE TABLE IF NOT EXISTS public.friendships (
  user_a UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  user_b UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_a, user_b),
  CHECK (user_a < user_b)
);
CREATE INDEX IF NOT EXISTS friendships_b ON public.friendships(user_b);

CREATE TABLE IF NOT EXISTS public.messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  recipient_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  body TEXT NOT NULL CHECK (length(body) BETWEEN 1 AND 4000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  read_at TIMESTAMPTZ,
  CHECK (sender_id <> recipient_id)
);
-- One conversation is the messages between a pair, whoever sent them.
CREATE INDEX IF NOT EXISTS messages_pair ON public.messages
  (LEAST(sender_id, recipient_id), GREATEST(sender_id, recipient_id), created_at DESC);
CREATE INDEX IF NOT EXISTS messages_unread ON public.messages(recipient_id) WHERE read_at IS NULL;
COMMIT;
