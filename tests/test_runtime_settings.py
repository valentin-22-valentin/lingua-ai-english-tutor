from unittest.mock import patch
import pytest
from fastapi.testclient import TestClient
from backend.api import app
from backend.runtime_settings import validate_runtime
from test_tutor import MemoryDB


def test_production_rejects_auth_bypass_and_wildcard_without_exposing_values():
    with pytest.raises(RuntimeError) as error:
        validate_runtime({'APP_ENV':'production','AUTH_REQUIRED':'false','CORS_ORIGINS':'*',
                          'OPENAI_API_KEY':'private-value'})
    assert 'AUTH_REQUIRED' in str(error.value) and 'private-value' not in str(error.value)


def test_production_accepts_explicit_configuration():
    validate_runtime({'APP_ENV':'production','AUTH_REQUIRED':'true',
        'CORS_ORIGINS':'https://app.example.com', 'SUPABASE_URL':'https://db.example.com',
        'SUPABASE_KEY':'test', 'OPENAI_API_KEY':'test'})


def test_health_does_not_call_ai_or_expose_database_errors(monkeypatch):
    monkeypatch.setenv('APP_ENV','development')
    with TestClient(app) as client:
        assert client.get('/health/live').status_code == 200
        with patch('backend.api.get_database',return_value=MemoryDB({'schema_releases':[{'id':9}]})):
            assert client.get('/health/ready').status_code == 200
        with patch('backend.api.get_database',side_effect=RuntimeError('private-error')):
            response=client.get('/health/ready')
            assert response.status_code==503
            assert 'private-error' not in response.text
