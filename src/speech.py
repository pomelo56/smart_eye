import time
import threading
import subprocess

try:
    import pyttsx3
except ImportError:
    pyttsx3 = None

from src.config import SPEECH_RATE, SPEECH_VOLUME, SPEECH_THROTTLE_SECONDS


class SpeechEngine:
    def __init__(self):
        self._last_speech_time = {}
        self._lock = threading.Lock()

        if pyttsx3 is not None:
            self._tts_engine = pyttsx3.init()
            self._tts_engine.setProperty('rate', SPEECH_RATE)
            self._tts_engine.setProperty('volume', SPEECH_VOLUME)
        else:
            self._tts_engine = None

    def speak(self, text, category="info", priority=1):
        if not text:
            return

        throttle_seconds = SPEECH_THROTTLE_SECONDS.get(category, 0.0)

        with self._lock:
            key = (category, text)
            now = time.time()
            if throttle_seconds > 0 and key in self._last_speech_time:
                if now - self._last_speech_time[key] < throttle_seconds:
                    return
            self._last_speech_time[key] = now

        threading.Thread(target=self._speak, args=(text,), daemon=True).start()

    def _speak(self, text):
        if self._tts_engine is not None:
            self._tts_engine.say(text)
            self._tts_engine.runAndWait()
        else:
            subprocess.run(['say', text], check=False)

    def reset_throttle(self, category=None):
        with self._lock:
            if category is None:
                self._last_speech_time.clear()
            else:
                keys_to_remove = [k for k in self._last_speech_time if k[0] == category]
                for key in keys_to_remove:
                    del self._last_speech_time[key]
