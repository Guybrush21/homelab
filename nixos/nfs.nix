{
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
    exports = ''
    /nfs 192.168.178.1/24(rw,fsid=0,no_subtree_check) 
    /nfs/murray 192.168.178.1/24(rw,nohide,insecure,no_subtree_check) 
    '';
  };
}
