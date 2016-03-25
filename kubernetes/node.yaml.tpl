#cloud-config
write-files:
  - path: /opt/bin/wupiao
    permissions: '0755'
    content: |
      #!/bin/bash
      # [w]ait [u]ntil [p]ort [i]s [a]ctually [o]pen
      [ -n "$1" ] && [ -n "$2" ] && while ! curl --output /dev/null \
        --silent --head --fail \
        http://${1}:${2}; do sleep 1 && echo -n .; done;
      exit $?
coreos:
  etcd2:
    listen-client-urls: http://0.0.0.0:2379,http://0.0.0.0:4001
    advertise-client-urls: http://0.0.0.0:2379,http://0.0.0.0:4001
    initial-cluster: master=http://192.168.1.10:2380
    proxy: on
  fleet:
    metadata: "role=node"
  units:
    - name: etcd2.service
      command: start
    - name: fleet.service
      command: start
    - name: flanneld.service
      command: start
    - name: docker.service
      command: start
    - name: setup-network-environment.service
      command: start
      content: |
        [Unit]
        Description=Setup Network Environment
        Documentation=https://github.com/kelseyhightower/setup-network-environment
        Requires=network-online.target
        After=network-online.target

        [Service]
        ExecStartPre=-/usr/bin/mkdir -p /opt/bin
        ExecStartPre=/usr/bin/curl -L -o /opt/bin/setup-network-environment -z /opt/bin/setup-network-environment https://github.com/kelseyhightower/setup-network-environment/releases/download/v1.0.0/setup-network-environment
        ExecStartPre=/usr/bin/chmod +x /opt/bin/setup-network-environment
        ExecStart=/opt/bin/setup-network-environment
        RemainAfterExit=yes
        Type=oneshot
    - name: kube-proxy.service
      command: start
      content: |
        [Unit]
        Description=Kubernetes Proxy
        Documentation=https://github.com/kubernetes/kubernetes
        Requires=setup-network-environment.service
        After=setup-network-environment.service

        [Service]
        ExecStartPre=/usr/bin/curl -L -o /opt/bin/kube-proxy -z /opt/bin/kube-proxy https://storage.googleapis.com/kubernetes-release/release/v1.2.0/bin/linux/amd64/kube-proxy
        ExecStartPre=/usr/bin/chmod +x /opt/bin/kube-proxy
        # wait for kubernetes master to be up and ready
        ExecStartPre=/opt/bin/wupiao 192.168.1.10 8080
        ExecStart=/opt/bin/kube-proxy \
        --master=192.168.1.10:8080 \
        --logtostderr=true
        Restart=always
        RestartSec=10
    - name: kube-kubelet.service
      command: start
      content: |
        [Unit]
        Description=Kubernetes Kubelet
        Documentation=https://github.com/kubernetes/kubernetes
        Requires=setup-network-environment.service
        After=setup-network-environment.service

        [Service]
        EnvironmentFile=/etc/network-environment
        ExecStartPre=/usr/bin/curl -L -o /opt/bin/kubelet -z /opt/bin/kubelet https://storage.googleapis.com/kubernetes-release/release/v1.2.0/bin/linux/amd64/kubelet
        ExecStartPre=/usr/bin/chmod +x /opt/bin/kubelet
        # wait for kubernetes master to be up and ready
        ExecStartPre=/opt/bin/wupiao 192.168.1.10 8080
        ExecStart=/opt/bin/kubelet \
        --address=0.0.0.0 \
        --port=10250 \
        --hostname-override=${DEFAULT_IPV4} \
        --api-servers=192.168.1.10:8080 \
        --allow-privileged=true \
        --logtostderr=true \
        --cadvisor-port=4194 \
        --healthz-bind-address=0.0.0.0 \
        --tls-cert-file=/etc/kubernetes/ssl/worker.pem \
        --tls-private-key-file=/etc/kubernetes/ssl/worker-key.pem \
        --healthz-port=10248
        Restart=always
        RestartSec=10
  update:
    group: alpha
    reboot-strategy: off
ssh_authorized_keys:
    - ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAgEAj/rzBLHFU6+BDQ54oL0lboD8k6kRnq0b/a+xuasF53Y3GrM/CWT064CnD2F2Itsv2SDUR4ngzOS8oRNxxQWsz5E2GHhGID3eYEmmhabdoJV2oa5KSfYBcVxi4WcrNZCeJuqETJ+wSntJ6ooJKCpm0GuXCw+MDHX1n5OT7roZt2k/hAKJhlz6tw7lNoXZGwnvXFoiMrJJY64jT2Umn2xcqm8ZHZ+lVOozowYgr6J3HzOwGAkIAxeWkVxhK7g4X5QLwwkwZ6b/D0gf4jA7hlk7IytZUpdoksP+VST1pbPa1LFjOu26vmSfozZNWQLBuzd6G5uWBYbSunQVS92xUv9Nf5JVeKPCt1M/5NW7ASfDiaryMT5sPfz0Fn3JXcPEbzShKgJaCMo5mApVoVt+zz99QTKVFQxkrNFXw3nGhCT3rEIKmmg2hJt9843W1tIboaCLhHUyTH+v1RHK/jwSwSLSR5AIooe6vgSaFQVUIHtag+C2BwBnuJLaxaljCoLfrT0YatKO9paZhf7uPYR5D4ocYktmhNHZXpCXitWjyQbGMXUICPAeUahxDR1HPG3GXIXV5mKDOyqkOdqaODvKsQ7MUiXUoibxpfHwqqKbr4rFIlp2HbOAfyy346voyzdhUnTwSMxB9bXvGygMAI8EkB6Fi43MAUp2W1+JgiD1Y0J4jSM=