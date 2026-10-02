# 1. VPC Network
resource "google_compute_network" "ai_vpc" {
  name                    = "ai-vpc"
  auto_create_subnetworks = false
}

# 2. Private Subnet
resource "google_compute_subnetwork" "private" {
  name          = "ai-private-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.ai_vpc.id

  private_ip_google_access = true
}

# 3. Cloud Router (required for Cloud NAT)
resource "google_compute_router" "router" {
  name    = "ai-router"
  region  = var.region
  network = google_compute_network.ai_vpc.id
}

# 4. Cloud NAT (allows private VM to reach internet for Docker/model download)
resource "google_compute_router_nat" "nat" {
  name                               = "ai-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.private.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

# 5. Firewall: Allow IAP SSH (TCP 22) to GPU node
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "allow-iap-ssh"
  network = google_compute_network.ai_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IAP's IP range for TCP forwarding
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["gpu-node"]
}

# 6. Firewall: Allow Load Balancer health checks and traffic on port 8000
resource "google_compute_firewall" "allow_lb_healthcheck" {
  name    = "allow-lb-healthcheck"
  network = google_compute_network.ai_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["8000"]
  }

  # GCP Load Balancer health check IP ranges
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["gpu-node"]
}

# 7. Service Account for GPU Node (least privilege)
resource "google_service_account" "gpu_node_sa" {
  account_id   = "gpu-node-sa"
  display_name = "GPU Node Service Account"
}

resource "google_project_iam_member" "gpu_node_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gpu_node_sa.email}"
}

resource "google_project_iam_member" "gpu_node_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gpu_node_sa.email}"
}

# 8. Compute Node (Compute Engine VM in Private Subnet) — CPU + LightGBM by default,
#    GPU + vLLM optional when var.gpu_count > 0
resource "google_compute_instance" "gpu_node" {
  name         = "ai-gpu-node"
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["gpu-node"]

  boot_disk {
    initialize_params {
      # GPU path needs the Deep Learning VM image (CUDA pre-installed); CPU path uses plain Debian
      image = var.gpu_count > 0 ? "projects/deeplearning-platform-release/global/images/family/common-cu121-debian-11" : "projects/debian-cloud/global/images/family/debian-12"
      size  = var.gpu_count > 0 ? 100 : 30
      type  = "pd-ssd"
    }
  }

  network_interface {
    network    = google_compute_network.ai_vpc.id
    subnetwork = google_compute_subnetwork.private.id
    # No access_config block = no public IP (private only)
  }

  dynamic "guest_accelerator" {
    for_each = var.gpu_count > 0 ? [1] : []
    content {
      type  = var.gpu_type
      count = var.gpu_count
    }
  }

  scheduling {
    # GPU-attached VMs cannot live-migrate, so they must TERMINATE on host maintenance
    on_host_maintenance = var.gpu_count > 0 ? "TERMINATE" : "MIGRATE"
    automatic_restart   = true
  }

  service_account {
    email  = google_service_account.gpu_node_sa.email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = var.gpu_count > 0 ? templatefile("${path.module}/user_data_gpu.sh", {
    hf_token = var.hf_token
    model_id = var.model_id
  }) : file("${path.module}/user_data_cpu.sh")

  metadata = {
    enable-oslogin = "TRUE"
  }

  depends_on = [google_compute_router_nat.nat]
}

# 9. Instance Group (unmanaged) for the Load Balancer backend
resource "google_compute_instance_group" "gpu_group" {
  name      = "ai-gpu-group"
  zone      = var.zone
  instances = [google_compute_instance.gpu_node.self_link]

  named_port {
    name = "vllm"
    port = 8000
  }
}

# 10. Health Check
resource "google_compute_health_check" "vllm_hc" {
  name               = "vllm-health-check"
  timeout_sec        = 10
  check_interval_sec = 30

  http_health_check {
    port         = 8000
    request_path = "/health"
  }
}

# 11. Backend Service
resource "google_compute_backend_service" "vllm_backend" {
  name                  = "vllm-backend"
  protocol              = "HTTP"
  port_name             = "vllm"
  load_balancing_scheme = "EXTERNAL"
  timeout_sec           = 300
  health_checks         = [google_compute_health_check.vllm_hc.id]

  backend {
    group           = google_compute_instance_group.gpu_group.id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

# 12. URL Map
resource "google_compute_url_map" "vllm_url_map" {
  name            = "vllm-url-map"
  default_service = google_compute_backend_service.vllm_backend.id
}

# 13. HTTP Proxy
resource "google_compute_target_http_proxy" "vllm_proxy" {
  name    = "vllm-http-proxy"
  url_map = google_compute_url_map.vllm_url_map.id
}

# 14. Global Forwarding Rule (External IP -> LB)
resource "google_compute_global_forwarding_rule" "vllm_fwd" {
  name                  = "vllm-forwarding-rule"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  target                = google_compute_target_http_proxy.vllm_proxy.id
  ip_protocol           = "TCP"
}
