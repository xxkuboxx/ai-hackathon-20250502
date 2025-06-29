variable "project_id" {
  description = "The GCP project ID."
  type        = string
  default     = "ai-hackathon-20250502"
}

variable "frontend_origins" {
  description = "CORS設定で許可するフロントエンドのオリジン（ドメイン）リスト(terraform.tfvarsで管理)"
  type        = list(string)
  default     = ["http://localhost:3000"]
  sensitive   = true
}
