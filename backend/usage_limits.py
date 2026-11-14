"""Bounded per-process request guard for development; use a shared limiter in production."""
import time
from collections import defaultdict, deque
from threading import Lock

from backend.tutor_engine import TutorError


class UsageLimiter:
    def __init__(self, count=20, window=60, max_keys=10000):
        self.count, self.window, self.max_keys = count, window, max_keys
        self.events = defaultdict(deque)
        self.lock = Lock()

    def claim(self, key):
        now = time.monotonic()
        with self.lock:
            for stale in [k for k, events in self.events.items() if not events or now - events[-1] >= self.window]:
                del self.events[stale]
            if key not in self.events and len(self.events) >= self.max_keys:
                raise TutorError(429, "A szolgáltatás terhelt. Próbáld újra később.")
            events = self.events[key]
            while events and now - events[0] >= self.window:
                events.popleft()
            if len(events) >= self.count:
                raise TutorError(429, "Túl sok kérés. Várj egy percet, majd próbáld újra.")
            events.append(now)
