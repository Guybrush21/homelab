# /etc/nixos/k3s.nix
{ config, pkgs, ... }:

{
  services.k3s = {
    enable = true;
    role = "server";  # single-node cluster

    extraFlags = toString [
      "--disable=traefik"
      "--disable=servicelb"
      "--write-kubeconfig-mode=644"
    ];
  };

  networking.firewall = {
    allowedTCPPorts = [
      6443  # k3s API server
      10250 # kubelet metrics
    ];
    trustedInterfaces = [
      "cni0"       # Container Network Interface
      "flannel.1"  # Flannel overlay network (k3s default)
    ];
  };

  environment.systemPackages = with pkgs; [
    kubectl
    k9s
    fluxcd
    sops
    age
    git
  ];

  environment.variables = {
    KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
  };
}
