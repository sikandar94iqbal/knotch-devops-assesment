terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }

  # Remote state in GCS gives us locking (via GCS's native object generation
  # checks) and a single shared source of truth for CI and any human
  # operator running `terraform plan` locally.
  #
  # This bucket lives in the DEV GCP project (see terraform/bootstrap,
  # run once against the dev project) - dev and prod each get their own
  # project and their own state bucket, not a shared one. That's a
  # deliberate isolation choice: nothing about dev's state, IAM, or quota
  # can affect prod, or vice versa.
  #
  # REPLACE_WITH_DEV_TF_STATE_BUCKET: from `terraform output bucket_name`
  # after bootstrapping the dev project - see the README bootstrap section.
  # A backend can't be provisioned by the same Terraform run that needs it.
  backend "gcs" {
    bucket = "knotch-dev-tfstate"
    prefix = "tenant-platform/dev"
  }
}
