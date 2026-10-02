output "load_balancer_ip" {
  description = "External IP address of the Load Balancer (API endpoint)"
  value       = google_compute_global_forwarding_rule.vllm_fwd.ip_address
}

output "api_endpoint" {
  description = "vLLM API endpoint URL"
  value       = "http://${google_compute_global_forwarding_rule.vllm_fwd.ip_address}/v1"
}

output "gpu_node_name" {
  description = "Name of the compute node (CPU/LightGBM by default, GPU/vLLM if var.gpu_count > 0)"
  value       = google_compute_instance.gpu_node.name
}

output "gpu_node_zone" {
  description = "Zone of the compute node"
  value       = google_compute_instance.gpu_node.zone
}

output "iap_ssh_command" {
  description = "Command to SSH into the GPU node via IAP"
  value       = "gcloud compute ssh ${google_compute_instance.gpu_node.name} --zone=${google_compute_instance.gpu_node.zone} --tunnel-through-iap"
}
