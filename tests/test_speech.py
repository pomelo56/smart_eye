import time
import threading
from unittest.mock import patch, MagicMock
import pytest

from src.speech import SpeechEngine


class TestSpeechEngine:

    @pytest.fixture
    def engine(self):
        with patch('src.speech.pyttsx3') as mock_pyttsx3:
            mock_engine = MagicMock()
            mock_pyttsx3.init.return_value = mock_engine
            engine = SpeechEngine()
            engine._tts_engine = mock_engine
            yield engine

    def test_speak_basic(self, engine):
        engine.speak("Hello World")
        engine._tts_engine.say.assert_called_once_with("Hello World")
        engine._tts_engine.runAndWait.assert_called_once()

    def test_throttle_same_category_same_content(self, engine):
        engine.speak("前方有障碍物", category="obstacle")
        engine.speak("前方有障碍物", category="obstacle")
        assert engine._tts_engine.say.call_count == 1

    def test_throttle_different_category_same_content(self, engine):
        engine.speak("检测到物品", category="obstacle")
        engine.speak("检测到物品", category="takeout")
        assert engine._tts_engine.say.call_count == 2

    def test_throttle_same_category_different_content(self, engine):
        engine.speak("前方有人", category="obstacle")
        engine.speak("前方有椅子", category="obstacle")
        assert engine._tts_engine.say.call_count == 2

    def test_reset_throttle_all(self, engine):
        engine.speak("障碍物警告", category="obstacle")
        engine.speak("障碍物警告", category="obstacle")
        assert engine._tts_engine.say.call_count == 1

        engine.reset_throttle()

        engine.speak("障碍物警告", category="obstacle")
        assert engine._tts_engine.say.call_count == 2

    def test_reset_throttle_specific_category(self, engine):
        engine.speak("障碍物警告", category="obstacle")
        engine.speak("外卖提醒", category="takeout")
        assert engine._tts_engine.say.call_count == 2

        engine.reset_throttle(category="obstacle")

        engine.speak("障碍物警告", category="obstacle")
        engine.speak("外卖提醒", category="takeout")
        assert engine._tts_engine.say.call_count == 3

    def test_ocr_category_zero_throttle(self, engine):
        for i in range(5):
            engine.speak("识别到文字", category="ocr")
        assert engine._tts_engine.say.call_count == 5

    def test_throttle_expires_after_time(self, engine):
        engine.speak("障碍物", category="obstacle")
        assert engine._tts_engine.say.call_count == 1

        engine._last_speech_time[("obstacle", "障碍物")] = time.time() - 4.0

        engine.speak("障碍物", category="obstacle")
        assert engine._tts_engine.say.call_count == 2

    def test_speak_does_not_block_main_thread(self, engine):
        def slow_say(text):
            time.sleep(0.5)

        engine._tts_engine.say.side_effect = slow_say

        start_time = time.time()
        engine.speak("测试语音", category="info")
        elapsed = time.time() - start_time

        assert elapsed < 0.3

    def test_default_category_and_priority(self, engine):
        engine.speak("默认测试")
        engine._tts_engine.say.assert_called_once_with("默认测试")

    def test_empty_text_skipped(self, engine):
        engine.speak("")
        engine._tts_engine.say.assert_not_called()

    def test_none_text_skipped(self, engine):
        engine.speak(None)
        engine._tts_engine.say.assert_not_called()
