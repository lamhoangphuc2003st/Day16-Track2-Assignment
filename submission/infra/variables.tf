variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP Zone"
  type        = string
  default     = "us-central1-a"
}

variable "hf_token" {
  description = "Hugging Face Token for gated models (like Gemma)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "model_id" {
  description = "Hugging Face Model ID to serve"
  type        = string
  default     = "google/gemma-4-E2B-it"
}

variable "machine_type" {
  description = "GCE Machine Type for the compute node. Default is a small CPU-only machine for the LightGBM lab; switch to a GPU-capable type (e.g. n1-standard-4) when setting gpu_count > 0 for the optional vLLM path"
  type        = string
  default     = "e2-medium"
}

variable "gpu_type" {
  description = "GPU accelerator type (only used when gpu_count > 0)"
  type        = string
  default     = "nvidia-tesla-t4"
}

variable "gpu_count" {
  description = "Number of GPUs to attach. Default 0 = CPU-only node (LightGBM). Set to 1 to opt into the GPU + vLLM LLM path"
  type        = number
  default     = 0
}
