# infrastructure/apis.tf

# --- APIの有効化 ---
# これらのリソースは、Terraformで管理される他のリソースが依存する、
# またはアプリケーションが必要とする可能性のあるGCPサービスAPIを有効化します。
# `disable_on_destroy = false` は、TerraformでこれらのAPI有効化設定リソースを削除しても、
# 実際のAPIが無効化されることを防ぎます。プロジェクトのAPIは一度有効化したら、
# Terraformの管理外でも有効であり続けることが一般的です。

# Cloud Run API
resource "google_project_service" "run_api" {
  project            = var.project_id
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

# Artifact Registry API
resource "google_project_service" "artifactregistry_api" {
  project            = var.project_id
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

# Identity and Access Management (IAM) API
# IAMポリシーやサービスアカウントの管理に必要です。
resource "google_project_service" "iam_api" {
  project            = var.project_id
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

# Cloud Build API
# コンテナイメージのビルドとプッシュに使用される可能性があります。
resource "google_project_service" "cloudbuild_api" {
  project            = var.project_id
  service            = "cloudbuild.googleapis.com"
  disable_on_destroy = false
}

# Vertex AI API
# AI/ML機能（例: Geminiモデル）の利用に必要です。
resource "google_project_service" "vertex_api" {
  project            = var.project_id
  service            = "aiplatform.googleapis.com"
  disable_on_destroy = false
}

# Cloud Storage API (storage.tf でバケットを作成するために暗黙的に必要ですが、明示的に記述することもできます)
# resource "google_project_service" "storage_api" {
#   project            = var.project_id
#   service            = "storage.googleapis.com"
#   disable_on_destroy = false
# }

# Secret Manager API (今回は使用しませんが、一般的に利用されるため参考としてコメントアウト)
# resource "google_project_service" "secretmanager_api" {
#   project            = var.project_id
#   service            = "secretmanager.googleapis.com"
#   disable_on_destroy = false
# }
