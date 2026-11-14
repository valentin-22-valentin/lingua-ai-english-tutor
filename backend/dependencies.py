"""Lazy client construction; imports do not call external services."""
import os
from functools import lru_cache
from pathlib import Path

from dotenv import load_dotenv
from openai import OpenAI
from supabase import create_client

from backend.tutor_engine import TutorService

load_dotenv(Path(__file__).resolve().parents[1] / ".env")


@lru_cache
def get_database():
    return create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_KEY"])


@lru_cache
def get_openai():
    return OpenAI(api_key=os.environ["OPENAI_API_KEY"], timeout=30, max_retries=1)


def get_tutor():
    return TutorService(get_database(), get_openai(), os.getenv("OPENAI_MODEL", "gpt-4o-mini"))
