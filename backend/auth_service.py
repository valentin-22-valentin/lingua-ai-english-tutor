"""Fresh Auth-only client: signing in never mutates the cached admin database client."""
import os
from supabase import create_client, ClientOptions
from backend.tutor_engine import TutorError


def auth_client():
    return create_client(os.environ['SUPABASE_URL'],
        os.getenv('SUPABASE_PUBLISHABLE_KEY') or os.environ['SUPABASE_KEY'],
        options=ClientOptions(persist_session=False, auto_refresh_token=False))


def session_response(response):
    session = response.session
    if not session:
        return {'confirmation_required': True}
    return {'profile_id': str(response.user.id), 'access_token': session.access_token,
        'refresh_token': session.refresh_token, 'expires_in': session.expires_in}


def ensure_profile(db, user, username='Tanuló'):
    username = username.strip() if isinstance(username, str) else 'Tanuló'
    if not 2 <= len(username) <= 24 or any(ord(character) < 32 for character in username):
        username = 'Tanuló'
    rows = db.table('profiles').select('id').eq('id', str(user.id)).execute().data
    if not rows:
        # Only the verified Auth user ID can be initialized. Concurrent login is safe via PK upsert.
        db.table('profiles').upsert({'id': str(user.id), 'username': username,
            'native_lang_code': 'hu', 'target_lang_code': 'en', 'app_lang_code': 'hu',
            'current_level': None}, on_conflict='id', ignore_duplicates=True).execute()
