import logging
import os
import subprocess
import tempfile
from typing import Optional

from music21 import converter
from pydub import AudioSegment

from exceptions import AudioSynthesisException

logger = logging.getLogger(__name__)

class AudioSynthesisService:
    def __init__(self):
        # SoundFontのパスを取得
        self.soundfont_path = f"GeneralUser GS v1.472.sf2"
        if not os.path.exists(self.soundfont_path):
            logger.error(f"SoundFontファイルが見つかりません: {self.soundfont_path}")
            raise AudioSynthesisException(detail=f"SoundFontファイルが見つかりません: {self.soundfont_path}")
        logger.info(f"SoundFontパス: {self.soundfont_path}")

    async def synthesize_musicxml_to_mp3(self, musicxml_content: str) -> bytes:
        """
        MusicXMLコンテンツをMP3バイト列に変換します。
        :param musicxml_content: MusicXMLの文字列データ
        :return: 生成されたMP3ファイルのバイト列
        """
        logger.info("MusicXMLからMP3への合成を開始します。")
        with tempfile.TemporaryDirectory() as tmpdir:
            musicxml_path = os.path.join(tmpdir, "input.musicxml")
            midi_path = os.path.join(tmpdir, "output.mid")
            wav_path = os.path.join(tmpdir, "output.wav")
            mp3_path = os.path.join(tmpdir, "output.mp3")

            try:
                # 1. MusicXMLをファイルに保存
                with open(musicxml_path, "w", encoding="utf-8") as f:
                    f.write(musicxml_content)
                logger.debug(f"MusicXMLを一時ファイルに保存しました: {musicxml_path}")

                # 2. MusicXMLをMIDIに変換 (music21)
                score = converter.parse(musicxml_path)
                score.write('midi', fp=midi_path)
                logger.debug(f"MusicXMLからMIDIへの変換が完了しました: {midi_path}")

                # 3. MIDIをWAVに変換 (FluidSynth)
                # -T wav: 出力形式をWAVに指定
                # -F <file>: 出力ファイルパスを指定
                # -r 44100: サンプリングレートを指定
                # -L warning: FluidSynthのログレベルをwarningに設定
                fluidsynth_cmd = [
                    "fluidsynth",
                    "-ni",  # no-interaction, no-shell
                    "-a", "file",
                    "-o", "synth.audio-channels=2",
                    "-T", "wav",
                    "-F", wav_path,
                    "-r", "44100",
                    # "-L", "warning",
                    self.soundfont_path,
                    midi_path,
                ]
                logger.debug(f"FluidSynthコマンド: {' '.join(fluidsynth_cmd)}")
                # subprocess.run(fluidsynth_cmd, check=True, capture_output=True)
                process = subprocess.run(fluidsynth_cmd, capture_output=True, text=True, check=False)
                logger.debug(f"MIDIからWAVへの変換が完了しました: {wav_path}")

                if process.returncode != 0:
                    logger.error(f"FluidSynthコマンドの実行に失敗しました。終了コード: {process.returncode}")
                    logger.error(f"FluidSynth stdout:\n{process.stdout}")
                    logger.error(f"FluidSynth stderr:\n{process.stderr}") # ★★★ この内容が重要 ★★★
                    # 元の例外を発生させるか、詳細情報を含めたカスタム例外を発生
                    raise subprocess.CalledProcessError(process.returncode, process.args, output=process.stdout, stderr=process.stderr)


                # 4. WAVをMP3に変換 (pydub)
                audio = AudioSegment.from_wav(wav_path)
                # 192kbit/s の品質でMP3にエクスポート
                audio.export(mp3_path, format="mp3", bitrate="192k")
                logger.debug(f"WAVからMP3への変換が完了しました: {mp3_path}")

                # 5. MP3ファイルを読み込んでバイト列として返す
                with open(mp3_path, "rb") as f:
                    mp3_data = f.read()
                logger.info("MusicXMLからMP3への合成が成功しました。")
                return mp3_data

            except Exception as e:
                logger.error(f"MusicXMLからMP3への合成中にエラーが発生しました: {e}", exc_info=True)
                raise AudioSynthesisException(detail=str(e))

# 依存性注入のための関数
_audio_synthesis_service_instance: Optional[AudioSynthesisService] = None

def get_audio_synthesis_service() -> AudioSynthesisService:
    global _audio_synthesis_service_instance
    if _audio_synthesis_service_instance is None:
        _audio_synthesis_service_instance = AudioSynthesisService()
    return _audio_synthesis_service_instance
