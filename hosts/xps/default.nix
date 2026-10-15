# xps - a Dell XPS 13 9380 that stopped being a laptop.
#
# It sits closed next to the router on ethernet and mains, and serves media.
# No desktop, no greeter, no impermanence: this is plain NixOS with the
# services it runs, and the whole configuration is this file plus disk.nix
# and hardware.nix beside it.
#
# Changing it: edit, commit, push, then on the machine
#
#   sudo nixos-rebuild switch --flake github:jimzer/kiwami-hosts#xps
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware.nix
    ./disk.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "xps";
  networking.useDHCP = true;

  time.timeZone = "Europe/Zurich";
  i18n.defaultLocale = "en_US.UTF-8";

  # [[ Never sleep ]]
  #
  # A closed lid is the normal state of this machine, not a request to
  # suspend, and neither is an idle timeout. All four sleep modes are refused
  # outright rather than merely not triggered, so nothing can ask politely
  # and succeed.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandleLidSwitchExternalPower = "ignore";
  };

  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };

  powerManagement.enable = false;

  # Running closed and warm for years is what ages the battery, not the
  # workload. Capping the charge is the cheap half of that; the other half is
  # leaving the vents clear, which no amount of config can do.
  services.thermald.enable = true;
  services.tlp = {
    enable = true;
    settings.STOP_CHARGE_THRESH_BAT0 = 80;
  };

  # [[ Reaching it ]]
  #
  # Tailscale SSH rather than authorized_keys: the tailnet decides who
  # connects, so there are no keys to distribute or rotate on a machine
  # nobody sits at.
  services.tailscale = {
    enable = true;
    extraUpFlags = [ "--ssh" ];
  };

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  # [[ Media ]]
  #
  # The external SSD. nofail because a server that drops to emergency mode
  # over an unplugged drive is worse than one serving nothing: the first
  # cannot be fixed remotely, and the second can.
  fileSystems."/stash" = {
    device = "/dev/disk/by-label/stash";
    fsType = "ext4";
    options = [ "nofail" "noatime" ];
  };

  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };

  # Hardware transcoding on the Intel chip. Whiskey Lake, so the iHD driver.
  # It handles H.264 and HEVC and predates AV1 - an AV1 file falls back to
  # the CPU, which on a mobile i7 is not worth attempting at 4K. Keep AV1 off
  # the library.
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [ intel-media-driver vpl-gpu-rt ];
  };

  # Jellyfin cannot open /dev/dri without these, and the failure is a silent
  # fallback to CPU transcoding rather than an error.
  users.users.jellyfin.extraGroups = [ "video" "render" ];

  # The acquisition side. sabnzbd downloads, radarr and sonarr decide what to
  # download and where to file it, prowlarr holds the indexer definitions so
  # the other two are configured once.
  #
  # None of their real configuration lives here: indexers, API keys, root
  # folders and quality profiles are in SQLite under /var/lib/<name>, because
  # these apps were built around a web UI writing to a database. That is the
  # part worth backing up, and the part an agent can drive over their REST
  # APIs instead of anybody opening a browser.
  # unrar is unfree - "unfreeRedistributable", so it may be shipped but not
  # modified - and sabnzbd needs it because Usenet posts are RAR archives.
  # Allowed by name rather than opening the gate with allowUnfree, so the
  # next thing that wants an unfree licence has to say so too.
  nixpkgs.config.allowUnfreePredicate =
    pkg: builtins.elem (lib.getName pkg) [ "unrar" ];

  services.sabnzbd.enable = true;
  services.radarr.enable = true;
  services.sonarr.enable = true;
  services.prowlarr.enable = true;

  # [[ The machine itself ]]

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  nix.optimise.automatic = true;

  # Otherwise the journal grows to a tenth of the disk and the first symptom
  # is a rebuild that cannot complete.
  services.journald.extraConfig = "SystemMaxUse=1G";

  users.users.jimzer = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };

  security.sudo.wheelNeedsPassword = false;

  # What is wanted at the end of an ssh connection, and nothing more. Plain
  # nixpkgs neovim rather than a configured one: this machine is for editing
  # a config file and reading a log, not for living in.
  environment.systemPackages = with pkgs; [
    neovim
    git
    curl
    wget
    htop
    tmux
    rsync
    pciutils
    usbutils
  ];

  environment.variables.EDITOR = "nvim";

  system.stateVersion = "26.05";
}
