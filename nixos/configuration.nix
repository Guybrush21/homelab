{ config, lib, pkgs, ... }:
{
  imports =
    [ ./hardware-configuration.nix
      ./k3s.nix
      ./backup.nix
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Boot-menu entry for memtest86+ so RAM can be tested without a USB stick.
  # Pick it from the systemd-boot menu and let it run overnight.
  boot.loader.systemd-boot.memtest86.enable = true;

  boot.kernel.sysctl."net.ipv4.ip_unprivileged_port_start" = 80;

  networking.hostName = "elaine";
  networking.networkmanager = {
    enable = true;
  };

  networking.useDHCP = false;
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 80 443 53 2049 111 4000 4001 4002 20048 ];
    allowedUDPPorts = [ 53 51820 2049 111 4000 4001 4002 20048]; 
    allowedTCPPortRanges = [{ from = 50101; to = 50300; }];
    allowedUDPPortRanges = [{ from = 50101; to = 50300; }];
    trustedInterfaces = ["flannel.1" "cni+"];
  };

  # NFS CONFIG
  fileSystems."/nfs/murray" = {
    device = "/mnt/murray";
    fsType = "none";
    options = [ "bind" ];
  };

  services.nfs.server = {
    enable = true;
    ## fixed port for nfsv3
    lockdPort = 4001;
    mountdPort = 4002;
    statdPort = 4000;
    extraNfsdConfig = '''';
    exports = ''
    /nfs 192.168.178.1/24(rw,fsid=0,no_subtree_check) 
    /nfs/murray 192.168.178.1/24(rw,nohide,insecure,no_subtree_check) 
    '';
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  time.timeZone = "Europe/Rome";
  i18n.defaultLocale = "en_US.UTF-8";

  programs.zsh.enable = true;
  programs.zsh.enableCompletion = true;

  users.users.jigen = {
    shell = pkgs.zsh;
    isNormalUser = true;
    description = "jigen";
    extraGroups = [ "wheel" "docker" "networkmanager" ];
  };
  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false; 
    };
  };

  programs.nix-ld.enable = true;

  # Essential packages
  nixpkgs.config.allowUnfree = true; 
  environment.systemPackages = with pkgs; [
    neovim
    vim
    git
    htop
    curl
    wget
    restic
    chezmoi
    podman-compose
    zsh
    starship 
    fzf
    gcc
    podlet
    opencode
    nodejs
    tmux
    kubectl
    kubernetes-validate
    unzip
    terraform
    kubernetes-helm
    lazygit
    smartmontools   
    lm_sensors     
    dmidecode     
  ];

  # RAID - ensure array name is consistent.
  # mdadm --monitor refuses to start without a destination, which is why
  # mdmonitor.service sat in "failed". There is no mail relay on this box, so
  # array events go to the journal and get broadcast to logged-in terminals.
  boot.swraid.mdadmConf = ''
    ARRAY /dev/md/murray metadata=1.2 UUID=701968c3-2f49-de3f-b9a9-8e4c011c4abe name=elaine:murray
    PROGRAM ${pkgs.writeShellScript "mdadm-alert" ''
      event="$1"; device="$2"; component="''${3:-}"
      message="mdadm: $event on $device ''${component:+($component)}"
      echo "$message" | ${pkgs.systemd}/bin/systemd-cat -t mdadm-alert -p warning
      ${pkgs.util-linux}/bin/wall "$message" || true
    ''}
  '';

  # Ensure jigen owns the murray mount for easy access
  systemd.tmpfiles.rules = [
    "d /mnt/murray/jigen 0755 jigen users -"
    "d /var/lib/homelab-data 0755 jigen users -"
    "d /var/lib/homelab-data/secrets 0700 jigen users -"
  ];

  # Create symlink for media in jigen's home
  system.activationScripts.mediaSymlink = lib.stringAfter [ "users" ] ''
    if [ ! -L /home/jigen/media ]; then
      mkdir -p /home/jigen
      ln -sf /mnt/murray/jigen/media /home/jigen/media
    fi
  '';

  # Continuously monitor disk health and warn on failures.
  services.smartd = {
    enable = true;
    autodetect = true;
    notifications.wall.enable = true;
  };

  systemd.settings.Manager = {
    RuntimeWatchdogSec = "30s";
    RebootWatchdogSec = "2m";
  };


  # NixOS version - don't change after install
  system.stateVersion = "25.11";
}
