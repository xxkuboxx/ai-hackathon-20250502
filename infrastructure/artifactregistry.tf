# infrastructure/artifactregistry.tf

# --- Artifact Registry リポジトリ ---
# SessionMUSEバックエンドのDockerイメージを保存するためのリポジトリです。
# アプリケーションのコンテナイメージはここにプッシュされ、
# (Terraform管理外の) Cloud Runサービスなどから参照されることを想定しています。

resource "google_artifact_registry_repository" "backend_repo" {
  project       = var.project_id
  location      = "us-east5"
  repository_id = "sessionmuse-backend-repo" # リポジトリID (プロジェクト内で一意)
  description   = "SessionMUSEバックエンドアプリケーションのDockerイメージリポジトリ"
  format        = "DOCKER" # フォーマット: Dockerイメージ

  # `depends_on` は、`google_project_service.artifactregistry_api` が `apis.tf` に定義されているため、
  # Terraformが自動的に依存関係を解決することを期待します。
  # もし明示的な依存が必要な場合は、 `depends_on = [google_project_service.artifactregistry_api]` を追加します。
  # (ただし、`google_project_service` は `var.project_id` にしか依存しないため、通常は不要です。)
}

resource "google_artifact_registry_repository" "frontend_repo" {
  project       = var.project_id
  location      = "us-east5"
  repository_id = "sessionmuse-frontend-repo" # リポジトリID (プロジェクト内で一意)
  description   = "SessionMUSEフロントエンドアプリケーションのDockerイメージリポジトリ"
  format        = "DOCKER"
}
