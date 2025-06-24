"""
音声ファイル変換サービス

WebMやAAC形式の音声ファイルをWAV形式に変換する機能を提供します。
"""

import io
import logging
from typing import BinaryIO, Optional
from pydub import AudioSegment
from pydub.exceptions import CouldntDecodeError

logger = logging.getLogger(__name__)


class AudioConversionError(Exception):
    """音声変換エラー"""
    pass


class AudioConversionService:
    """音声ファイル変換サービス"""
    
    @staticmethod
    def convert_to_wav(
        audio_data: bytes, 
        source_format: str,
        output_sample_rate: int = 44100,
        output_channels: int = 1
    ) -> bytes:
        """
        音声データをWAV形式に変換
        
        Args:
            audio_data: 変換元の音声データ
            source_format: 変換元の形式 ('webm', 'aac', 'm4a', 'mp3', 'mp4')
            output_sample_rate: 出力サンプルレート (デフォルト: 44100Hz)
            output_channels: 出力チャンネル数 (デフォルト: 1=モノラル)
            
        Returns:
            WAV形式の音声データ
            
        Raises:
            AudioConversionError: 変換に失敗した場合
        """
        try:
            logger.info(f"音声変換開始: {source_format} -> WAV")
            
            # 入力データからAudioSegmentを作成
            audio_io = io.BytesIO(audio_data)
            
            # 形式に応じてAudioSegmentを読み込み
            if source_format.lower() in ['webm']:
                # WebM形式 (通常はOpusコーデック)
                try:
                    audio = AudioSegment.from_file(audio_io, format="webm")
                except CouldntDecodeError:
                    # WebMが読めない場合、OGGとして試行
                    audio_io.seek(0)
                    audio = AudioSegment.from_file(audio_io, format="ogg")
                    
            elif source_format.lower() in ['aac']:
                # AAC形式
                audio = AudioSegment.from_file(audio_io, format="aac")
                
            elif source_format.lower() in ['m4a', 'mp4']:
                # M4A/MP4形式
                audio = AudioSegment.from_file(audio_io, format="m4a")
                
            elif source_format.lower() in ['mp3']:
                # MP3形式
                audio = AudioSegment.from_file(audio_io, format="mp3")
                
            else:
                raise AudioConversionError(f"サポートされていない音声形式: {source_format}")
            
            logger.info(f"元の音声情報 - チャンネル数: {audio.channels}, サンプルレート: {audio.frame_rate}Hz, 長さ: {len(audio)}ms")
            
            # 出力形式に変換
            if audio.channels != output_channels:
                if output_channels == 1:
                    audio = audio.set_channels(1)  # モノラルに変換
                else:
                    audio = audio.set_channels(output_channels)
                    
            if audio.frame_rate != output_sample_rate:
                audio = audio.set_frame_rate(output_sample_rate)
            
            # WAV形式でエクスポート
            output_io = io.BytesIO()
            audio.export(output_io, format="wav")
            wav_data = output_io.getvalue()
            
            logger.info(f"音声変換完了 - 出力サイズ: {len(wav_data)} bytes")
            return wav_data
            
        except CouldntDecodeError as e:
            error_msg = f"音声ファイルをデコードできませんでした ({source_format}): {str(e)}"
            logger.error(error_msg)
            raise AudioConversionError(error_msg) from e
            
        except Exception as e:
            error_msg = f"音声変換中にエラーが発生しました ({source_format}): {str(e)}"
            logger.error(error_msg)
            raise AudioConversionError(error_msg) from e
    
    @staticmethod
    def needs_conversion(mime_type: str) -> bool:
        """
        指定されたMIMEタイプが変換を必要とするかチェック
        
        Args:
            mime_type: チェックするMIMEタイプ
            
        Returns:
            変換が必要な場合True（WAV以外はすべて変換）
        """
        # WAV形式以外はすべて変換対象
        wav_types = [
            "audio/wav",
            "audio/x-wav"
        ]
        return mime_type not in wav_types
    
    @staticmethod
    def get_source_format_from_mime_type(mime_type: str) -> str:
        """
        MIMEタイプから変換元形式を取得
        
        Args:
            mime_type: MIMEタイプ
            
        Returns:
            pydubで使用する形式名
        """
        mime_to_format = {
            "audio/webm": "webm",
            "audio/aac": "aac",
            "audio/mp4": "m4a", 
            "audio/x-m4a": "m4a",
            "audio/mpeg": "mp3"
        }
        return mime_to_format.get(mime_type, "unknown")