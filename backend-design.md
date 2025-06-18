# SessionMUSE バックエンドAPI詳細設計書


## 1. はじめに
本設計書は、APIの実装の指針となることを目的とします。


## 2. 設計方針・アーキテクチャ
 * フレームワーク: FastAPI を採用します。Pythonの型ヒントを活用した高速な開発、自動的なデータバリデーション、対話的なAPIドキュメント（Swagger UI, ReDoc）生成といった特徴が、本プロジェクトの迅速な開発に適しています。
 * 実行環境: アプリケーションをコンテナ化し、Google Cloud Run 上で実行します。これにより、トラフィックに応じた自動スケーリングを実現し、サーバー管理のオーバーヘッドを削減します。
 * 非同期処理: FastAPIの `async def` を全面的に活用し、ファイルI/Oや外部API（Gemini, Cloud Storage）呼び出しをノンブロッキングで実行します。これにより、単一のインスタンスでも高い同時接続性能を確保します。
 * データ永続化: アップロードされた音声ファイルおよび生成されたバッキングトラックは、Google Cloud Storage (GCS) に一時的なオブジェクトとして保存します。GCSのライフサイクルポリシーを設定し、ファイルは一定期間（例: 24時間、設定値で管理）後に自動的に削除されます。元音声ファイルも処理後GCSにアップロードし、同様にライフサイクル管理の対象とします。
 * AI連携: LangChain ライブラリを利用して、Google Gemini 1.5 Pro APIとの連携を抽象化・効率化します。特に、複数の音声解析タスク（キー、BPM、コード進行、ジャンル推定など）やバッキングトラック生成指示を、LangGraphを用いて並列処理可能なワークフローとして構築し、処理時間の短縮とロジックの明確化を図ります。
 * **認証**: Cloud Runサービス間の呼び出しにおいては、呼び出し元サービス（フロントエンドのCloud Runサービス）のサービスアカウントに、本バックエンドCloud Runサービスを呼び出すための適切なIAMロール (`roles/run.invoker`) を付与することで認証を行います。これにより、認可されたサービスからのリクエストのみを受け付けます。

### 2.1. 設定管理
本アプリケーションにおける設定値は、以下の方法で管理します。
 * **環境変数**: デプロイ環境ごとに異なる基本的な設定値（GCSバケット名、Geminiモデル名、ログレベルなど）は環境変数を通じてアプリケーションに渡します。
 * **Google Cloud Secret Manager**: APIキー（Gemini APIキーなど）やデータベース認証情報のようなセンシティブな情報は、Google Cloud Secret Managerに保存し、アプリケーション実行時に安全に読み込みます。
 * 管理対象の例:
    *   `GCS_UPLOAD_BUCKET`: ユーザーがアップロードした元ファイルを保存するGCSバケット名
    *   `GCS_TRACK_BUCKET`: AIが生成したバッキングトラックを保存するGCSバケット名
    *   `GEMINI_API_KEY_SECRET_NAME`: Gemini APIキーが格納されているSecret Managerのシークレット名 (例: `projects/YOUR_PROJECT_ID/secrets/GEMINI_API_KEY/versions/latest`)
    *   `GEMINI_MODEL_NAME`: 使用するGeminiモデル名 (例: `gemini-1.5-pro-latest`)
    *   `LOG_LEVEL`: アプリケーションログのレベル (例: `INFO`, `DEBUG`)
    *   `SIGNED_URL_EXPIRATION_SECONDS`: GCS署名付きURLの有効期間（秒数、例: 3600秒 = 1時間）
    *   `GCS_LIFECYCLE_DAYS`: GCSオブジェクトの自動削除までの日数 (例: 1日)
    *   `MAX_FILE_SIZE_MB`: アップロードファイルの最大サイズ（MB単位、例: 100）


## 3. 技術スタック（詳細）
| カテゴリ | 技術/ライブラリ | 用途 |
|---|---|---|
| Webフレームワーク | FastAPI | APIエンドポイントの構築、リクエスト/レスポンス処理 |
| ASGIサーバー | Uvicorn | FastAPIアプリケーションの実行 |
| データバリデーション | Pydantic | リクエスト/レスポンスのデータモデル定義とバリデーション |
| ファイルアップロード | python-multipart | FastAPIでのファイルアップロード処理に必須 |
| AIモデル連携 | LangChain, google-generativeai, LangGraph | Gemini 1.5 Pro APIの呼び出し、プロンプト管理、AI処理ワークフローの構築 |
| クラウドストレージ | google-cloud-storage | Google Cloud Storageへのファイルアップロード/ダウンロード |
| 設定管理 | python-dotenv (ローカル開発用), Google Cloud Secret Manager | 環境変数、機密情報の管理 |


## 4. APIエンドポイント詳細


### 4.1. 音声処理API
 * エンドポイント: `POST /api/process`
 * 説明: ユーザーがアップロードした音声ファイルを解析し、バッキングトラックを生成して、それらの情報を返却します。
 * リクエスト:
   * Content-Type: `multipart/form-data`
   * Body:
     * `file`: `UploadFile` (音声ファイル: MP3, WAV)
 * 成功レスポンス (200 OK):
   * Content-Type: `application/json`
   * Body: (`ProcessResponse` モデル)
 * エラーレスポンス: (詳細は「6.1. エラーレスポンス体系」参照)
   * 400 Bad Request: リクエスト形式不正、必須パラメータ欠損。(`ErrorCode.INVALID_REQUEST`)
   * 413 Payload Too Large: ファイルサイズ超過。(`ErrorCode.FILE_TOO_LARGE`)
   * 415 Unsupported Media Type: 対応していないファイル形式。(`ErrorCode.UNSUPPORTED_MEDIA_TYPE`)
   * 500 Internal Server Error: 予期せぬサーバーエラー。(`ErrorCode.INTERNAL_SERVER_ERROR`)
   * 503 Service Unavailable: 外部サービス（Gemini, GCS）連携エラー。(`ErrorCode.EXTERNAL_SERVICE_ERROR`)
 * 処理フロー:
   1.  **リクエスト受信・パース**: FastAPIが音声ファイルをパースします。
   2.  **バリデーション**:
       *   ファイルのMIMEタイプが `audio/mpeg` (MP3) または `audio/wav` であることを確認します。違反時は 415エラー (`ErrorCode.UNSUPPORTED_MEDIA_TYPE`)。
       *   ファイルサイズが設定値 (`MAX_FILE_SIZE_MB`) を超えていないか確認します。超過時は 413エラー (`ErrorCode.FILE_TOO_LARGE`)。
   3.  **ファイルの一時保存とGCSアップロード (元ファイル)**:
       *   一意なID（例: UUID）を生成します。
       *   アップロードされた音声ファイルを、この一意なIDをファイル名としてGCSの指定バケット（環境変数 `GCS_UPLOAD_BUCKET` の `original/` プレフィックスなど）にストリーミングアップロードします。アップロード失敗時は 503エラー (`ErrorCode.GCS_UPLOAD_ERROR`)。
       *   GCS上のファイルパス（または署名付きURL）を後続の処理で使用します。
   4.  **音声解析 (AI) とバッキングトラック生成 (AI) - LangGraphによるワークフロー**:
       *   **LangGraphワークフローの構築**: 以下のタスクをノードとして定義し、依存関係に基づいてエッジで結びつけ、並列実行可能なグラフを構築します。
           *   **タスクA: キー推定**: GCS上の音声ファイルを参照し、Gemini APIにキーを推定させるプロンプトを送信。
           *   **タスクB: BPM推定**: GCS上の音声ファイルを参照し、Gemini APIにBPMを推定させるプロンプトを送信。
           *   **タスクC: コード進行推定**: GCS上の音声ファイルを参照し、Gemini APIにコード進行を推定させるプロンプトを送信。
           *   **タスクD: ジャンル推定**: GCS上の音声ファイルを参照し、Gemini APIに楽曲のジャンルを推定させるプロンプトを送信。
           *   **タスクE (タスクA,B,C,Dに依存): バッキングトラック生成**: タスクA～Dで得られた解析結果（キー、BPM、コード進行、AI推定ジャンル）に基づき、Gemini APIにバッキングトラック（MP3形式）の生成を指示するプロンプトを送信。
       *   **ワークフロー実行**: 構築したLangGraphワークフローを実行します。各AIタスクの実行中にGemini APIでエラーが発生した場合は、グラフ全体のエラーとして処理し、503エラー (`ErrorCode.ANALYSIS_FAILED` または `ErrorCode.GENERATION_FAILED`)。
       *   **結果の集約**: ワークフローの実行結果から、`AnalysisResult` モデルに必要な情報（キー、BPM、コード進行、AI推定ジャンル）と、生成されたバッキングトラックデータを取得します。
   5.  **生成ファイルのGCSアップロード (バッキングトラック)**:
       *   ワークフローから得られた生成バッキングトラック（MP3）を、ステップ3で生成した一意なIDに関連付けられたファイル名でGCSの指定バケット（環境変数 `GCS_TRACK_BUCKET` の `generated/` プレフィックスなど）にアップロードします。アップロード失敗時は 503エラー (`ErrorCode.GCS_UPLOAD_ERROR`)。
   6.  **レスポンス生成**:
       *   GCSにアップロードしたバッキングトラックの署名付きURL（ダウンロード可能な一時URL）を生成します。有効期間は設定値 (`SIGNED_URL_EXPIRATION_SECONDS`) に従います。URL生成失敗時は 500エラー (`ErrorCode.INTERNAL_SERVER_ERROR`)。
       *   GCSにアップロードしたオリジナルファイルの署名付きURLも同様に生成します。
       *   `ProcessResponse` モデルに従ってJSONレスポンスを構築し、クライアントに返却します。`AnalysisResult` にはAIが推定したジャンル (`genre_by_ai`) も含めます。
   7.  **クリーンアップ**:
       *   GCSのライフサイクル設定により、アップロードされた元ファイルと生成ファイルは一定期間（設定値 `GCS_LIFECYCLE_DAYS`）後に自動削除されます。ローカルに一時ファイルを作成した場合は、処理完了後に速やかに削除します。


### 4.2. AIチャットAPI
 * エンドポイント: `POST /api/chat`
 * 説明: ユーザーからの質問と音楽的文脈を受け取り、AIからのアドバイスを生成して返却します。
 * リクエスト:
   * Content-Type: `application/json`
   * Body: (`ChatRequest` モデル)
 * 成功レスポンス (200 OK):
   * Content-Type: `application/json` (デフォルト) または `text/event-stream` (ストリーミング時)
   * Body: (`ChatMessage` モデル、ストリーミングの場合は `data: {ChatMessage}\n\n` 形式)
 * エラーレスポンス: (詳細は「6.1. エラーレスポンス体系」参照)
   * 400 Bad Request: リクエスト形式不正、必須パラメータ欠損。(`ErrorCode.INVALID_REQUEST`)
   * 503 Service Unavailable: Gemini API連携エラー。(`ErrorCode.EXTERNAL_SERVICE_ERROR`)
 * 処理フロー:
   1.  **リクエスト受信・バリデーション**: リクエストボディを `ChatRequest` モデルとして受信し、Pydanticによるバリデーションを実行します。バリデーションエラー時は 400エラー (`ErrorCode.INVALID_REQUEST`)。
   2.  **システムプロンプト構築**: AIの役割と応答スタイルを定義するシステムプロンプトを準備します。
       > あなたは「SessionMUSE」という名の、親切で創造的なAI音楽パートナーです。音楽理論に詳しく、抽象的な表現も具体的なアイデアに変換できます。ユーザーの音楽制作をサポートし、インスピレーションを与えるような、ポジティブで建設的なフィードバックを提供してください。
   3.  **コンテキスト付与**: リクエストに含まれる `analysis_context` (キー, BPM, コード進行、AI推定ジャンル) と `messages` (過去の対話履歴) をプロンプトに組み込み、AIに現在の文脈を正確に伝えます。
   4.  **AIモデル呼び出し**: LangChainを介して、構築したプロンプトをGemini 1.5 Pro APIに送信します。Gemini API呼び出し時にエラーが発生した場合（例: APIキー不正、レート制限、コンテンツフィルターなど）は 503エラー (`ErrorCode.GEMINI_API_ERROR`)。
   5.  **レスポンス返却**:
       *   クライアントがリクエストヘッダー `Accept: text/event-stream` を指定した場合: Gemini APIから逐次的に返されるテキストトークンを、FastAPIの `StreamingResponse` を使ってSSE (Server-Sent Events) 形式でフロントエンドに転送します。各メッセージは `ChatMessage` のJSON形式で `data:` フィールドに含めます。
       *   上記以外の場合 (デフォルト): APIからの応答が完了してから、`ChatMessage` モデルに従ったJSONレスポンスを返却します。
   6.  **エラー処理**: 処理中に予期せぬエラーが発生した場合は、500エラー (`ErrorCode.INTERNAL_SERVER_ERROR`) を返却します。


## 5. データモデル (Pydantic)
APIのI/Oは以下のPydanticモデルによって厳密に定義されます。


```python
from pydantic import BaseModel, Field, HttpUrl
from typing import List, Literal, Optional
from enum import Enum


# エラーコード定義 (エラーレスポンスで使用)
class ErrorCode(str, Enum):
    INVALID_REQUEST = "INVALID_REQUEST"
    INVALID_FILE_TYPE = "INVALID_FILE_TYPE"
    FILE_TOO_LARGE = "FILE_TOO_LARGE"
    UNSUPPORTED_MEDIA_TYPE = "UNSUPPORTED_MEDIA_TYPE"
    GCS_UPLOAD_ERROR = "GCS_UPLOAD_ERROR"
    ANALYSIS_FAILED = "ANALYSIS_FAILED"
    GENERATION_FAILED = "GENERATION_FAILED"
    GEMINI_API_ERROR = "GEMINI_API_ERROR"
    EXTERNAL_SERVICE_ERROR = "EXTERNAL_SERVICE_ERROR"
    INTERNAL_SERVER_ERROR = "INTERNAL_SERVER_ERROR"
    AUTHENTICATION_REQUIRED = "AUTHENTICATION_REQUIRED" # 将来的な拡張用
    FORBIDDEN_ACCESS = "FORBIDDEN_ACCESS"           # 将来的な拡張用
    RATE_LIMIT_EXCEEDED = "RATE_LIMIT_EXCEEDED"     # 将来的な拡張用


class ErrorDetail(BaseModel):
    code: ErrorCode
    message: str
    detail: Optional[str] = None


class ErrorResponse(BaseModel):
    error: ErrorDetail


# /api/process -------------------


class AnalysisResult(BaseModel):
    key: str = Field(..., description="解析されたキー", example="C Major")
    bpm: int = Field(..., description="解析されたBPM", example=120, gt=0)
    chords: List[str] = Field(..., description="解析されたコード進行", example=["C", "G", "Am", "F"])
    genre_by_ai: str = Field(..., description="AIによって推定されたジャンル", example="Pop Ballad")


class ProcessResponse(BaseModel):
    analysis: AnalysisResult
    backing_track_url: HttpUrl = Field(..., description="生成されたバッキングトラックの署名付きURL")
    original_file_url: Optional[HttpUrl] = Field(None, description="アップロードされたオリジナルファイルの署名付きURL (確認用など)")


# /api/chat ----------------------


class ChatMessage(BaseModel):
    role: Literal["user", "assistant"]
    content: str


class ChatRequest(BaseModel):
    messages: List[ChatMessage] = Field(..., min_items=1)
    analysis_context: Optional[AnalysisResult] = Field(None, description="現在の楽曲の解析情報（AI推定ジャンル含む）") # フロントエンドから送信される際は AnalysisResult の形式に従う


```


## 6. セキュリティと堅牢性


### 6.1. エラーハンドリングとレスポンス体系
FastAPIの例外ハンドラ (`@app.exception_handler`) を利用して、アプリケーション内で発生する様々な例外を捕捉し、一貫性のあるエラーレスポンスをクライアントに返却します。


*   **共通エラーレスポンス**: 全てのエラーレスポンスは、`ErrorResponse` モデルに従ったJSON形式で返却されます。
    ```json
    {
      "error": {
        "code": "ERROR_CODE_ENUM",
        "message": "人が読んで理解できるエラーメッセージ",
        "detail": "（オプション）エラーに関する追加の詳細情報やデバッグ情報"
      }
    }
    ```
*   **HTTPステータスコード**:
    *   `4xx`系: クライアント側の起因によるエラー。
    *   `5xx`系: サーバー側の起因によるエラー。
*   **具体的なエラーケースと対応**:
    *   **リクエストバリデーションエラー (Pydantic)**: FastAPIが自動的に422 Unprocessable Entityを返しますが、これをカスタムハンドラで捕捉し、`ErrorCode.INVALID_REQUEST` と共に統一形式の `ErrorResponse` で400 Bad Requestとして返却します。
    *   **ビジネスロジックエラー**:
        *   ファイルタイプ不正: `ErrorCode.UNSUPPORTED_MEDIA_TYPE` (415)
        *   ファイルサイズ超過: `ErrorCode.FILE_TOO_LARGE` (413)
        *   LangGraphワークフローでの音声解析失敗: `ErrorCode.ANALYSIS_FAILED` (503)
        *   LangGraphワークフローでのバッキングトラック生成失敗: `ErrorCode.GENERATION_FAILED` (503)
    *   **外部サービス連携エラー**:
        *   Gemini API呼び出しエラー (個々のタスク内、タイムアウト、APIキー不正、レート制限超過など): `ErrorCode.GEMINI_API_ERROR` (503). LangGraph内のノードで発生した場合、グラフ全体のエラーとして集約される。
        *   Google Cloud Storage 操作エラー (アップロード/ダウンロード失敗): `ErrorCode.GCS_UPLOAD_ERROR` (503)
    *   **認証・認可エラー** (将来的な拡張を見据え):
        *   認証トークンなし・不正: `ErrorCode.AUTHENTICATION_REQUIRED` (401)
        *   権限不足: `ErrorCode.FORBIDDEN_ACCESS` (403)
    *   **レート制限超過エラー**: `ErrorCode.RATE_LIMIT_EXCEEDED` (429)
    *   **予期せぬサーバーエラー**: `ErrorCode.INTERNAL_SERVER_ERROR` (500)。この場合、詳細なエラー情報はログに出力し、クライアントには汎用的なメッセージを返します。


### 6.2. タイムアウト
Gemini APIやその他の外部サービス呼び出しには、`httpx` などのHTTPクライアントライブラリの機能を利用して、適切なタイムアウト値（例: 30秒〜120秒、設定値で管理）を設定し、リクエストが長時間ハングアップするのを防ぎます。タイムアウト発生時は `ErrorCode.EXTERNAL_SERVICE_ERROR` またはより具体的なエラーコード (例: `ErrorCode.GEMINI_API_ERROR` の `detail` にタイムアウト情報を付加) を返却します。LangGraphの各ノード実行時にもタイムアウトを設定します。


### 6.3. リソース管理
Cloud Runのインスタンス設定（メモリ、CPU）を、音声処理の負荷やGemini APIとの連携に必要なリソースを考慮して適切に設定します。特にファイル処理やAIモデルのレスポンスサイズによってはメモリ消費が増える可能性があるため、十分なマージンを確保します。


### 6.4. ロギング
標準の`logging`モジュールとGoogle Cloud Loggingを連携させ、以下の情報を構造化ログとして記録し、モニタリングとデバッグに役立てます。
 * リクエスト情報: (メソッド, パス, IPアドレス, User-Agent, リクエストID)
 * 認証情報: (呼び出し元サービスアカウントIDなど、個人情報は適切にマスク)
 * LangGraphワークフローの実行ID、各ノードの開始・終了、処理時間
 * 外部API呼び出し: (対象サービス, リクエストパラメータ（機密情報マスク）, レスポンスステータス, レイテンシ)
 * エラー情報: (エラーコード, メッセージ, スタックトレース)
 * 設定値でログレベル（DEBUG, INFO, WARNING, ERROR）を制御可能にします。

