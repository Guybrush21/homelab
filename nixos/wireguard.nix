# WireGuard VPN on elaine. The Fritz!Box keeps its own WireGuard as a
# break-glass way in for when elaine is down (see README).
{ config, lib, pkgs, ... }:

let
  port = 51820;
  subnet = "10.13.13";
  # Outside /nix/store, which is world-readable. Generated on first start and
  # covered by the restic backup of /var/lib/homelab-data.
  keyFile = "/var/lib/homelab-data/secrets/wireguard.key";

  # One entry per device. `sudo wg-add-client <name> <ip>` prints the line to
  # paste here, plus the config and QR code for the device itself. Client
  # private keys never touch this box.
  clients = {
    telefono-nic = { ip = "10.13.13.2"; publicKey = "YW1XlBouNXzu3EnKm74k6KA0FvTMbD69y9UlK9z61jY="; };
  };

  wg-add-client = pkgs.writeShellApplication {
    name = "wg-add-client";
    runtimeInputs = [ pkgs.wireguard-tools pkgs.qrencode ];
    text = ''
      if [ $# -ne 2 ]; then
        echo "usage: sudo wg-add-client <name> <${subnet}.N>" >&2
        exit 1
      fi
      name=$1
      ip=$2

      priv=$(wg genkey)
      pub=$(wg pubkey <<< "$priv")
      server_pub=$(wg pubkey < ${keyFile})

      # Full tunnel: everything goes through home, ads blocked by AdGuard
      # everywhere. For LAN-only use AllowedIPs = 192.168.178.0/24, ${subnet}.0/24
      conf="[Interface]
      PrivateKey = $priv
      Address = $ip/32
      DNS = 192.168.178.51

      [Peer]
      PublicKey = $server_pub
      Endpoint = elaine.pw:${toString port}
      AllowedIPs = 0.0.0.0/0"

      qrencode -t ansiutf8 <<< "$conf"
      echo
      echo "$conf"
      echo
      echo "Add to clients in nixos/wireguard.nix, then nixos-rebuild switch:"
      echo "    $name = { ip = \"$ip\"; publicKey = \"$pub\"; };"
    '';
  };
in
{
  networking.wireguard.interfaces.wg0 = {
    ips = [ "${subnet}.1/24" ];
    listenPort = port;
    privateKeyFile = keyFile;
    generatePrivateKeyFile = true;
    peers = lib.mapAttrsToList (name: c: {
      inherit name;
      inherit (c) publicKey;
      allowedIPs = [ "${c.ip}/32" ];
    }) clients;
  };

  # Clients reach the LAN and the internet as elaine, so neither the Fritz!Box
  # nor the other LAN hosts need a route back to ${subnet}.0/24.
  networking.nat = {
    enable = true;
    internalInterfaces = [ "wg0" ];
    externalInterface = "enp10s0";
  };

  networking.firewall.allowedUDPPorts = [ port ];

  environment.systemPackages = [ pkgs.wireguard-tools wg-add-client ];
}
