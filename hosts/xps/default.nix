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
  # A 2TB Crucial X8, exFAT, holding 1.5T of films. Not reformatted to ext4
  # because there is nowhere to put the contents while it happens - the
  # machine's own disk is 476G - and shrinking exFAT in place with the only
  # copy of the data on it is not a trade worth making. Revisit when the
  # array gets real disks.
  #
  # exFAT has no Unix permissions: every file takes the uid and gid given at
  # mount time. So the mount hands the whole drive to one group and the
  # services join it, rather than anybody chowning anything.
  #
  # nofail because a server that drops to emergency mode over an unplugged
  # drive is worse than one serving nothing - the first cannot be fixed
  # remotely and the second can.
  fileSystems."/stash" = {
    device = "/dev/disk/by-uuid/65B7-9532";
    fsType = "exfat";
    options = [
      "nofail"
      "noatime"
      "uid=0"
      "gid=${toString config.users.groups.media.gid}"
      "umask=0002"   # files 664, directories 775: the group can write
    ];
  };

  # Fixed gid, because the mount option above is a number and has to match a
  # group that exists.
  users.groups.media.gid = 985;

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

  # Jellyfin cannot open /dev/dri without video and render, and the failure
  # is a silent fallback to CPU transcoding rather than an error. media is
  # what lets it read /stash.
  users.users.jellyfin.extraGroups = [ "video" "render" "media" ];
  users.users.radarr.extraGroups = [ "media" ];
  users.users.sonarr.extraGroups = [ "media" ];
  users.users.sabnzbd.extraGroups = [ "media" ];

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

  services.sabnzbd = {
    enable = true;

    # Unlike the servarr apps, sabnzbd's config is an ini file the module
    # owns outright, and it takes its secrets from a separate file that is
    # merged over the top. So the key is declarative here in the sense that
    # matters: it is known before the service starts, without being in git
    # or in the store.
    secretFiles = [ "/var/lib/secrets/sabnzbd-secrets.ini" ];

    # The module writes the config read-only so this file stays the single
    # source of truth. Left that way deliberately: anything set through the
    # web interface would be silently reverted on the next rebuild, which is
    # a worse surprise than not being able to set it there at all.
    settings = {
      misc = {
        host = "0.0.0.0";
        # Downloads land on the media drive, not the system disk - 476G of
        # root would otherwise fill up behind a single season.
        download_dir = "/stash/Temp/.incomplete";
        complete_dir = "/stash/Temp";
      };
    };
  };

  # API keys from a file outside the store.
  #
  # Each of these generates a random key on first start and writes it into
  # its own database, which means the only way to learn it is to open the
  # web UI - and the only way to script the stack is to have known it in
  # advance. Setting it here inverts that: the keys exist before the
  # services do, so an agent can configure indexers, root folders and
  # download clients over the REST APIs without anybody clicking anything.
  #
  # environmentFiles rather than settings, because settings end up in the
  # nix store and the store is world readable. These files are written on
  # the machine with mode 600 and simply persist - there is no impermanence
  # here to wipe them.
  #
  # Generate them with:
  #   install -d -m 700 /var/lib/secrets
  #   printf 'RADARR__AUTH__APIKEY=%s\n' "$(head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n')" \
  #     > /var/lib/secrets/radarr.env
  services.radarr.environmentFiles = [ "/var/lib/secrets/radarr.env" ];
  services.sonarr.environmentFiles = [ "/var/lib/secrets/sonarr.env" ];
  services.prowlarr.environmentFiles = [ "/var/lib/secrets/prowlarr.env" ];

  # Make those files exist before anything reads them.
  #
  # systemd fails a unit whose EnvironmentFile is missing, so without this
  # the three services would not start on a machine that had never been
  # seeded - which is every fresh install. The keys are generated once and
  # then left alone, so a rebuild never changes a key that something has
  # already been configured with.
  #
  # An install can pre-seed these instead (nixos-anywhere --extra-files), in
  # which case this finds them already present and does nothing. That is the
  # path worth using: the keys are then known before the machine has booted
  # once, and the stack can be configured over its APIs immediately.
  systemd.services.servarr-secrets = {
    description = "Generate API keys for the servarr services";
    wantedBy = [ "multi-user.target" ];
    before = [ "radarr.service" "sonarr.service" "prowlarr.service" "sabnzbd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # 711, not 700. systemd reads an EnvironmentFile as root before it
      # drops privileges, so the servarr apps do not care - but sabnzbd
      # merges its own config as the sabnzbd user, and a directory it cannot
      # traverse is reported as "not found", which is a confusing way to
      # learn about a permission.
      install -d -m 711 /var/lib/secrets
      for s in radarr sonarr prowlarr; do
        f=/var/lib/secrets/$s.env
        if [ ! -s "$f" ]; then
          key=$(head -c 16 /dev/urandom | ${pkgs.coreutils}/bin/od -An -tx1 | tr -d " \n")
          printf "%s__AUTH__APIKEY=%s\n" "$(echo "$s" | tr "[:lower:]" "[:upper:]")" "$key" > "$f"
          chmod 600 "$f"
        fi
      done

      # sabnzbd reads its own secrets file, so it has to own it.
      if [ -e /var/lib/secrets/sabnzbd-secrets.ini ]; then
        chown sabnzbd:sabnzbd /var/lib/secrets/sabnzbd-secrets.ini
        chmod 600 /var/lib/secrets/sabnzbd-secrets.ini
      fi
    '';
  };
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
    extraGroups = [ "wheel" "media" ];

    # Belt and braces. Tailscale SSH is the normal way in, but it only works
    # once tailscaled has an identity - and a fresh install has none until
    # somebody authenticates it. A machine reachable only through the thing
    # that is not yet set up is a machine nobody can reach, which is how the
    # last install nearly went.
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCfo/AgwaTtwll3gj2IH76Ytuehwku/6IRVsoB4coFKHpGI4MQSpiOGObwXA/o9WlgnkyivQ86puWFB6SvN6cqVpVt3ol5g+wxnXUXX3N84stLggjAS6KyfuB3qN7JOFqcHFrLHdO2/6wCSIDjoQJfMJ7V2TMIOPZNXU4hg1gZ6LT8kxK0comu0AI0txax+KO6Q+SudzGrZwKWm0Oi3AU01+l4ItW4dId2DXvzKqhOyspKQYm4F8ZXToFx5kM5kUe3e5mx0Kqd3ryOROlRPSUiiprlL6iQTTCDKRXZ5AhoLpHGIvGVr/AIN1U7l/GcR3KcwK1qCh4VY8ole+PB+5CVQqgnKDW+Z5PL7PtEbiowAgFE5fYWR/acwjFijIxAHss37cr/L8eKTnLp2Psbr0gDRXNHvzUyN3SwPsO1yzslg6NwA1DcnM8hD4nCMd+MT2TeEc+uZafc6mgkV6kJcEgmza0+awVvsUvNWHFI9j5v/8JxnmQEGsIh0UxwN4XOZxJs= jimzer@jimis-macbook-pro.home"
    ];
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
