  {
    services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "elaine";
        "netbios name" = "elaine";
        "security" = "user";
        "hosts allow" = "192.168.178. 127.0.0.1 localhost";
        "hosts deny" = "0.0.0.0/0";
        "guest account" = "nobody";
      };
      "private" = {
        "path" = "/mnt/murray/media";
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0644";
        "directory mask" = "0755";
      };
    };

  };

  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };
}
