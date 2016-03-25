provider "cloudstack" {
    api_key       =  "${replace("${file("~/.terraform/nl2_cs_api_key")}", "\n", "")}"
    secret_key    =  "${replace("${file("~/.terraform/nl2_cs_secret_key")}", "\n", "")}"
    api_url       =  "https://nl2.mcc.schubergphilis.com/client/api"
}

resource "cloudstack_ssh_keypair" "kubernetes_coreos" {
  name = "kubernetes_coreos"
}

resource "cloudstack_network" "network" {
    count = "${lookup(var.counts, "network")}"
    name = "kubernetes-network${count.index+1}"
    display_text = "kubernetes-network${count.index+1}"
    cidr = "${lookup(var.cs_cidrs, "network")}"
    network_offering = "${lookup(var.offerings, "network")}"
    zone = "${lookup(var.cs_zones, "network")}"
}

resource "cloudstack_instance" "kube-master" {
  count = "${lookup(var.counts, "master")}"
  zone = "${lookup(var.cs_zones, "master")}"
  service_offering = "${lookup(var.offerings, "master")}"
  template = "${var.cs_template}"
  name = "kube-master-${count.index+1}"
  network = "${cloudstack_network.network.0.id}"
  expunge = "true"
  ipaddress = "192.168.1.10"
  user_data = "${file("../cloud-config/master.yaml")}"
  keypair = "kubernetes_coreos"

  provisioner "local-exec" {
    command = "cd ../ssl/ && ./generate-keys.sh"
  }
}

resource "null_resource" "provision_master" {
  depends_on = ["cloudstack_port_forward.ssh_api_server"]
  count = "${lookup(var.counts, "master")}"
  
  provisioner "remote-exec" {
    inline = ["sudo mkdir -p /etc/kubernetes/ssl"]
  }

  provisioner "file" {
    source = "/tmp/kube-ssl"
    destination = "~/kube-ssl"
  }

  provisioner "remote-exec" {
        inline = ["sudo mv ~/kube-ssl/*.pem /etc/kubernetes/ssl",
        "sudo chmod 600 /etc/kubernetes/ssl/*-key.pem",
        "sudo chown root:root /etc/kubernetes/ssl/*-key.pem",
        "sudo systemctl daemon-reload"
        ]
  }

  connection {
    host = "${cloudstack_ipaddress.public_ip.ipaddress}"
    user = "core"
    private_key = "${cloudstack_ssh_keypair.kubernetes_coreos.private_key}"
  }
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
  user_data = "${file("../cloud-config/node.yaml")}"
  keypair = "kubernetes_coreos"
}

resource "null_resource" "provision-worker"{
  depends_on = ["cloudstack_instance.kube-worker"]
  depends_on = ["cloudstack_port_forward.ssh_api_server"]
  count = "${lookup(var.counts, "worker")}"
   
  provisioner "remote-exec" {
    inline = ["sudo mkdir -p /etc/kubernetes/ssl"]
  }

  provisioner "file" {
    source = "/tmp/kube-ssl"
    destination = "~/kube-ssl"
  }
  
  provisioner "remote-exec" {
    inline = ["sudo mv ~/kube-ssl/*.pem /etc/kubernetes/ssl",
        "sudo chmod 600 /etc/kubernetes/ssl/*-key.pem",
        "sudo chown root:root /etc/kubernetes/ssl/*-key.pem",
        "cd /etc/kubernetes/ssl/ && sudo ln -s kube-worker-1-worker.pem worker.pem && sudo ln -s kube-worker-1-worker-key.pem worker-key.pem",
        "sudo systemctl daemon-reload"
    ]
    }
  connection {
    host = "${cloudstack_ipaddress.public_ip.ipaddress}"
    user = "core"
    port = 2222
    private_key = "${cloudstack_ssh_keypair.kubernetes_coreos.private_key}"
  }
}

resource "cloudstack_firewall" "firewall" {
  ipaddress = "${cloudstack_ipaddress.public_ip.0.id}"

  rule {
    source_cidr = "84.105.28.192/32"
    protocol = "tcp"
    ports = ["1222","2222","3222", "80","8080","30831","22","6443"]
  }

   rule {
    source_cidr = "195.66.90.65/24"
    protocol = "tcp"
    ports = ["1222","2222","3222", "80","8080","30831","22","6443"]
  }
}

resource "cloudstack_egress_firewall" "egress1" {
  network = "${cloudstack_network.network.0.name}"

  rule {
    source_cidr = "0.0.0.0/0"
    protocol = "tcp"
    ports = ["1-65535"]
  }
  rule {
    source_cidr = "0.0.0.0/0"
    protocol = "udp"
    ports = ["1-65535"]
  }
  rule {
    source_cidr = "0.0.0.0/0"
    protocol = "icmp"
  }
}

resource "cloudstack_ipaddress" "public_ip" {
  count = "${lookup(var.counts, "public_ip")}"
  network = "${cloudstack_network.network.0.id}"
  depends_on = ["cloudstack_instance.kube-master"]
  depends_on = ["cloudstack_instance.kube-worker"]
}

resource "cloudstack_port_forward" "worker-1" {
  ipaddress = "${cloudstack_ipaddress.public_ip.1.id}"
  depends_on = ["cloudstack_firewall.firewall"]
  depends_on = ["cloudstack_instance.kube-worker"]

  forward {
    protocol = "tcp"
    private_port = "22"
    public_port = "22"
    virtual_machine = "kube-worker-1"
  }
}

resource "cloudstack_port_forward" "ssh_api_server" {
  ipaddress = "${cloudstack_ipaddress.public_ip.0.id}"
  depends_on = ["cloudstack_firewall.firewall"]
  depends_on = ["cloudstack_instance.kube-master"]

  forward {
    protocol = "tcp"
    private_port = "22"
    public_port = "22"
    virtual_machine = "kube-master-1"
  }
  forward {
    protocol = "tcp"
    private_port = "8080"
    public_port = "8080"
    virtual_machine = "kube-master-1"
  }
  forward {
    protocol = "tcp"
    private_port = "6443"
    public_port = "6443"
    virtual_machine = "kube-master-1"
  }
}
