"""Verify duration on the server before paid transcription; client timers are not a limit."""
import io
import wave
from backend.tutor_engine import TutorError


def validate_recording(data):
    try:
        with wave.open(io.BytesIO(data), 'rb') as recording:
            rate, frames = recording.getframerate(), recording.getnframes()
            if (recording.getcomptype() != 'NONE' or recording.getnchannels() not in (1, 2)
                    or recording.getsampwidth() not in (1, 2, 3, 4) or not 8000 <= rate <= 48000):
                raise TutorError(415, 'PCM WAV hangfelvétel szükséges (8–48 kHz, mono vagy sztereó).')
            if frames < 1 or frames / rate > 16:
                raise TutorError(413, 'A hangfelvétel legfeljebb 16 másodperc lehet.')
            pcm = recording.readframes(frames)
            if len(pcm) != frames * recording.getnchannels() * recording.getsampwidth():
                raise TutorError(422, 'A hangfelvétel hiányos.')
            # Forward only the checked PCM frames, excluding appended/unknown chunks.
            # The upstream decoder must see exactly the duration we validated.
            canonical = io.BytesIO()
            with wave.open(canonical, 'wb') as output:
                output.setparams(recording.getparams())
                output.writeframes(pcm)
            return canonical.getvalue()
    except (wave.Error, EOFError, ValueError) as exc:
        raise TutorError(422, 'A WAV hangfelvétel hibás vagy hiányos.') from exc
