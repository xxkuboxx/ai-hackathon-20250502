resource "google_storage_bucket" "uploads_bucket" {
  name                        = "sessionmuse-uploads-${var.project_id}"
  location                    = "asia-northeast1"
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = 1
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [
    # This explicit dependency is not strictly necessary for bucket creation itself,
    # but can be useful if other resources depend on the provider's project setting.
    # provider.google
  ]
}

resource "google_storage_bucket" "tracks_bucket" {
  name                        = "sessionmuse-tracks-${var.project_id}"
  location                    = "asia-northeast1"
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = 1
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [
    # provider.google
  ]
}
