variable "cs_cidrs" {
  default = {
    network = "192.168.10.0/24"
  }
}

variable "cs_zones" {
  default = {
    network = "NL2"
    master = "NL2"
    worker = "NL2"
  }
}

variable "offerings" {
  default = {
    master = "mcc_v1.1vCPU.4GB.SBP1"
    worker = "mcc_v1.1vCPU.4GB.SBP1"
    network = "MCC-VPC-LB"
  }
}

variable "counts" {
  default = {
    network = "1"
    master = "1"
    worker = "1"
    public_ip = "2"
  }
}

variable "cs_template" {
	default = ""
}

variable "cs_zone" {
	description = "Cloudstack Zone"
	default = "BETA-SBP-DC-1"
}
