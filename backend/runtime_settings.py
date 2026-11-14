"""Deployment checks; never print credentials or contact external services."""
import os
from urllib.parse import urlparse


def validate_runtime(environ=None):
    env = os.environ if environ is None else environ
    if env.get('APP_ENV', 'development') != 'production':
        return
    problems = []
    if env.get('AUTH_REQUIRED', 'true').lower() != 'true':
        problems.append('AUTH_REQUIRED must be true')
    origins = [o.strip() for o in env.get('CORS_ORIGINS', '').split(',') if o.strip()]
    if not origins or any(urlparse(o).scheme != 'https' or not urlparse(o).hostname
                          or urlparse(o).username or urlparse(o).password
                          or urlparse(o).path not in ('', '/') for o in origins):
        problems.append('CORS_ORIGINS must list explicit HTTPS origins')
    for key in ('SUPABASE_URL', 'SUPABASE_KEY', 'OPENAI_API_KEY'):
        if not env.get(key, '').strip():
            problems.append(f'{key} is required')
    if problems:
        raise RuntimeError('Production configuration rejected: ' + '; '.join(problems))
