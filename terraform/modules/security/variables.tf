variable "project_id" {
  description = "GCP project ID the security policy is created in."
  type        = string
}

variable "name_prefix" {
  description = "Prefix applied to every resource name, e.g. \"tenant-dev\"."
  type        = string
}

variable "rate_limit_threshold_count" {
  description = "Requests allowed per client IP within rate_limit_threshold_interval_sec before Cloud Armor starts throttling."
  type        = number
  default     = 100
}

variable "rate_limit_threshold_interval_sec" {
  description = "Sliding window (seconds) the rate limit rule counts requests over."
  type        = number
  default     = 60
}
