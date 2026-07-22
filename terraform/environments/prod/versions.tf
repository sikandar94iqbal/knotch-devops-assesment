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

  # This bucket lives in the PROD GCP project (see terraform/bootstrap, run
  # a second time against the prod project) - a separate bucket from dev's,
  # in a separate project. Nothing about prod's state, IAM, or quota is
  # reachable from dev, or vice versa.
  #
  # REPLACE_WITH_PROD_TF_STATE_BUCKET: from `terraform output bucket_name`
  # after bootstrapping the prod project.
  backend "gcs" {
    bucket = "knotch-prod-tfstate"
    prefix = "tenant-platform/prod"
  }
}
