/**
 * Security module
 *
 * A Cloud Armor security policy attached to both the app's and ArgoCD's
 * backend Services via `GCPBackendPolicy` (in their respective Helm
 * charts, referencing this policy by name). Runs in front of every
 * request the global external LB forwards to either backend.
 *
 * Adaptive Protection (ML-based L7 DDoS defense) and a per-IP rate limit
 * are in place. Google's preconfigured WAF rulesets (sqli-stable,
 * xss-stable) were tried here originally but were pulled after they
 * produced a false positive that broke ArgoCD's own login redirect
 * (`/login?return_url=https%3A%2F%2F...` - a URL-encoded absolute URL in
 * a query param is a classic OWASP CRS false-positive trigger at default
 * strictness). Re-introducing WAF rules for real would need per-path/
 * per-parameter exclusions tuned against actual traffic first, rather
 * than a blanket preconfigured expression - see the design questions
 * answer in the README for the full writeup of this tradeoff.
 */

resource "google_compute_security_policy" "this" {
  project     = var.project_id
  name        = "${var.name_prefix}-armor-policy"
  description = "Rate limiting + adaptive DDoS defense for the ${var.name_prefix} backends (app + ArgoCD). No WAF rulesets - see module doc comment."

  # Google's ML-based L7 DDoS detection - flags/mitigates volumetric and
  # protocol attacks.
  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable = true
    }
  }

  # Per-client-IP rate limit - throttles a single source hammering a
  # backend before it can degrade service for everyone else.
  rule {
    action   = "throttle"
    priority = 2000
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = var.rate_limit_threshold_count
        interval_sec = var.rate_limit_threshold_interval_sec
      }
    }
    description = "Per-IP rate limit"
  }

  # Required catch-all - lowest priority, matches anything the rules above
  # didn't already deny.
  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow"
  }
}
