provider "cloudstack" {
    api_key       =  "${replace("${file("~/.terraform/nl2_cs_api_key")}", "\n", "")}"
    secret_key    =  "${replace("${file("~/.terraform/nl2_cs_secret_key")}", "\n", "")}"
    api_url       =  "https://nl2.mcc.schubergphilis.com/client/api"
}

resource "template_file" "master-config" {
    count = "${lookup(var.counts, "master")}"
    template = "${file("master.yaml.tpl")}"
    vars {
      terraform_hostname = "kube-master-1"
    }
}

resource "template_file" "node-config" {
    count = "${lookup(var.counts, "worker")}"
    template = "${file("node.yaml.tpl")}"
    vars {
      terraform_master_ip = "${cloudstack_instance.kube-master.0.ipaddress}"
    }
}

resource "cloudstack_vpc" "vpc" {
  count = "${lookup(var.counts, "vpc")}"
  name = "kubernetes-vpc${count.index+1}"
  cidr = "${lookup(var.cs_cidrs, "vpc")}"
  vpc_offering = "${lookup(var.offerings, "vpc")}"
  zone = "${lookup(var.cs_zones, "vpc")}"
}

resource "cloudstack_network" "network" {
  count = "${lookup(var.counts, "network")}"
  name = "kubernetes-network${count.index+1}"
  display_text = "kubernetes-network${count.index+1}"
  cidr = "${lookup(var.cs_cidrs, "network")}"
  network_offering = "${lookup(var.offerings, "network")}"
  zone = "${lookup(var.cs_zones, "network")}"
  vpc = "${element(cloudstack_vpc.vpc.*.name, count.index)}"
}

resource "cloudstack_instance" "kube-master" {
  count = "${lookup(var.counts, "master")}"
  zone = "${lookup(var.cs_zones, "master")}"
  service_offering = "${lookup(var.offerings, "master")}"
  template = "${var.cs_template}"
  name = "kube-master-${count.index+1}"
  network = "${cloudstack_network.network.0.id}"
  expunge = "true"
  user_data = "${element(template_file.master-config.*.rendered, count.index)}"
  keypair = "deployment"
}

resource "cloudstack_instance" "kube-worker" {
  depends_on = ["cloudstack_instance.kube-master"]
  count = "${lookup(var.counts, "worker")}"
  zone = "${lookup(var.cs_zones, "worker")}"
  service_offering = "${lookup(var.offerings, "worker")}"
  template = "${var.cs_template}"
  name = "kube-worker-${count.index+1}"
  network = "${cloudstack_network.network.0.id}"
  expunge = "true"
  user_data = "${element(template_file.node-config.*.rendered, count.index)}"
  keypair = "deployment"
}

resource "cloudstack_network_acl" "acl" {
  count = "${lookup(var.counts, "vpc")}"
  name = "kube-acl-${count.index+1}"
  vpc = "${element(cloudstack_vpc.vpc.*.id, count.index)}"
}

resource "cloudstack_network_acl_rule" "acl-rule" {
  count = "${lookup(var.counts, "vpc")}"
  aclid = "${element(cloudstack_network_acl.acl.*.id, count.index)}"

  rule {
    source_cidr = "84.105.28.192/32"
    protocol = "tcp"
    ports = ["1222","2222","3222", "80","8080","30831","22","6443"]
    action = "allow"
    traffic_type = "ingress"
  }

   rule {
    source_cidr = "195.66.90.65/24"
    protocol = "tcp"
    ports = ["1222","2222","3222", "80","8080","30831","22","6443"]
    action = "allow"
    traffic_type = "ingress"
  }
}

resource "cloudstack_ipaddress" "public_ip" {
  count = "${lookup(var.counts, "public_ip")}"
  network = "${cloudstack_network.network.0.id}"
  depends_on = ["cloudstack_instance.kube-master"]
  depends_on = ["cloudstack_instance.kube-worker"]
}

resource "cloudstack_port_forward" "worker" {
  ipaddress = "${cloudstack_ipaddress.public_ip.1.id}"
  depends_on = ["cloudstack_instance.kube-worker"]

  forward {
    protocol = "tcp"
    private_port = "22"
    public_port = "22"
    virtual_machine = "${cloudstack_instance.kube-worker.0.name}"
  }
}

resource "cloudstack_port_forward" "master" {
  ipaddress = "${cloudstack_ipaddress.public_ip.0.id}"

  forward {
    protocol = "tcp"
    private_port = "22"
    public_port = "22"
    virtual_machine = "${cloudstack_instance.kube-master.0.name}"
  }
  forward {
    protocol = "tcp"
    private_port = "8080"
    public_port = "8080"
    virtual_machine = "${cloudstack_instance.kube-master.0.name}"
  }
  forward {
    protocol = "tcp"
    private_port = "6443"
    public_port = "6443"
    virtual_machine = "${cloudstack_instance.kube-master.0.name}"
  }
}
