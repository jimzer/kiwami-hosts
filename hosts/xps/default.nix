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
  # Wifi, as a fallback for the cable.
  #
  # NetworkManager rather than networking.wireless. The declarative route
  # was tried first and was the wrong trade: it keeps the passphrase out of
  # this repository, which matters for an API key and barely at all for a
  # home wifi password, and in exchange it wants a PBKDF2 hash computed by
  # hand, a secrets file readable by a service that runs as its own user,
  # and a failure mode that says WRONG_KEY whichever of those is wrong.
  #
  # NetworkManager stores the connection under /var/lib/NetworkManager,
  # which persists because this machine has no impermanence. So it is set
  # once with nmcli and then it is simply true. The cost is that a reinstall
  # needs it set again - a fair price for one network on a machine that
  # lives on ethernet.
  networking.networkmanager = {
    enable = true;
    wifi.powersave = false;   # a server should not sleep its radio
  };

  # useDHCP and NetworkManager both managing interfaces is a fight neither
  # wins; NetworkManager does DHCP itself.
  networking.useDHCP = false;

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

  # The staging drive: the 500G Samsung T5 that was the installer stick until
  # there was a SanDisk to take over. Everything on it is undecided - things
  # downloaded but not yet promoted into the permanent library - which makes
  # it the one drive here that can be reformatted without a conversation.
  #
  # ext4, not exfat like /stash, because nothing plugs this one into a Mac.
  # That buys real Unix permissions, so the group is set by setgid bits on
  # the directories rather than by a mount option, and macOS cannot litter
  # it with AppleDouble files.
  fileSystems."/staging" = {
    device = "/dev/disk/by-uuid/e16cfe77-c40f-4730-b444-b63e87f9dfe4";
    fsType = "ext4";
    options = [ "nofail" "noatime" ];
  };

  services.jellyfin = {
    enable = true;
    # Deliberately not openFirewall. Everything here is reached over the
    # tailnet, and tailscale accepts its own traffic before the NixOS
    # firewall is consulted at all - INPUT jumps to ts-input first, which
    # accepts anything arriving on tailscale0. So closing the ports shuts
    # out the LAN and changes nothing for the tailnet.
    #
    # It matters because the Jellyfin password is deliberately trivial. The
    # tailnet is the authentication; a login page on the house wifi is not.
    openFirewall = false;

    # Hardware transcoding, stated here rather than clicked in the dashboard.
    #
    # Without this Jellyfin reports HardwareAccelerationType "none" and
    # transcodes on the CPU - which on a mobile i7 driving 4K is the
    # difference between playing and not. The failure is silent: it simply
    # uses the CPU and nobody is told.
    hardwareAcceleration = {
      enable = true;
      type = "vaapi";
      device = "/dev/dri/renderD128";
    };

    transcoding = {
      enableHardwareEncoding = true;
      # Whiskey Lake decodes these in hardware; AV1 it cannot, and an AV1
      # file will fall back to the CPU however this is set.
      hardwareDecodingCodecs = {
        h264 = true;
        hevc = true;
        vp8 = true;
        vp9 = true;
      };
      # Tone mapping for HDR into SDR clients. Expensive, and the usual
      # reason a 4K HDR file stutters on something that cannot display HDR.
      enableToneMapping = true;
      # Off, though the documentation recommends it for Gen9 and newer. The
      # low-power encode block on Whiskey Lake only does constant-QP rate
      # control, and Jellyfin asks for VBR with a target bitrate, so the
      # encoder refuses to open at all:
      #   Driver does not support VBR RC mode (supported modes: CQP)
      # The result is no transcode rather than a slower one.
      enableIntelLowPowerEncoding = false;
    };

    # Apply the above on every start, so the configuration here is the truth
    # rather than whatever was last clicked. It backs up encoding.xml first.
    forceEncodingConfig = true;
  };

  # Hardware transcoding on the Intel chip. Whiskey Lake, so the iHD driver.
  # It handles H.264 and HEVC and predates AV1 - an AV1 file falls back to
  # the CPU, which on a mobile i7 is not worth attempting at 4K. Keep AV1 off
  # the library.
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vpl-gpu-rt
      # OpenCL, which is not optional here: tone mapping runs as
      # tonemap_opencl, so without a runtime every HDR transcode dies with
      # "Failed to get number of OpenCL platforms: -1001" and Jellyfin
      # retries it forever. Decode and encode work without this; only HDR
      # breaks, which is why it looks fine until a 4K file is played.
      #
      # legacy1, not intel-compute-runtime: the current one supports 12th
      # Gen and newer, and this is Gen9.5. The wrong one installs happily
      # and changes nothing.
      intel-compute-runtime-legacy1
    ];
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

  # [[ The dashboard ]]
  #
  # http://xps, so nobody has to remember which of five ports a service is
  # on. More than a list of links: the widgets talk to each service's API,
  # so the page shows what is downloading, what is playing and how much of
  # /stash is left.
  #
  # The keys come from an environment file rather than being written here.
  # This repository is on GitHub and the nix store is world readable, so a
  # key in `services` below would be published twice over. Homepage expands
  # {{HOMEPAGE_VAR_X}} from its environment, and the environment comes from
  # the same /var/lib/secrets the services themselves read.
  services.homepage-dashboard = {
    enable = true;
    listenPort = 8082;
    environmentFiles = [ "/var/lib/secrets/homepage.env" ];

    # It refuses requests whose Host header it does not recognise, which is
    # a sensible default and a confusing error when you have not set it.
    allowedHosts = "xps,xps.tail2527fa.ts.net,100.92.38.81,localhost:8082";

    settings = {
      title = "xps";
      theme = "dark";
      headerStyle = "clean";
      layout = [
        { Media = { style = "row"; columns = 3; }; }
        { Acquisition = { style = "row"; columns = 3; }; }
      ];
    };

    services = [
      {
        Media = [
          {
            Jellyfin = {
              href = "http://xps:8096";
              description = "Films and series";
              widget = {
                type = "jellyfin";
                url = "http://127.0.0.1:8096";
                key = "{{HOMEPAGE_VAR_JELLYFIN_KEY}}";
                enableBlocks = true;
                enableNowPlaying = true;
              };
            };
          }
          {
            Radarr = {
              href = "http://xps:7878";
              description = "Films";
              widget = {
                type = "radarr";
                url = "http://127.0.0.1:7878";
                key = "{{HOMEPAGE_VAR_RADARR_KEY}}";
              };
            };
          }
          {
            Sonarr = {
              href = "http://xps:8989";
              description = "Series";
              widget = {
                type = "sonarr";
                url = "http://127.0.0.1:8989";
                key = "{{HOMEPAGE_VAR_SONARR_KEY}}";
              };
            };
          }
        ];
      }
      {
        Acquisition = [
          {
            SABnzbd = {
              href = "http://xps:8080";
              description = "Downloads";
              widget = {
                type = "sabnzbd";
                url = "http://127.0.0.1:8080";
                key = "{{HOMEPAGE_VAR_SABNZBD_KEY}}";
              };
            };
          }
          {
            Prowlarr = {
              href = "http://xps:9696";
              description = "Indexers";
              widget = {
                type = "prowlarr";
                url = "http://127.0.0.1:9696";
                key = "{{HOMEPAGE_VAR_PROWLARR_KEY}}";
              };
            };
          }
        ];
      }
    ];

    widgets = [
      {
        resources = {
          cpu = true;
          memory = true;
          disk = [ "/" "/stash" ];
        };
      }
      {
        search = {
          provider = "duckduckgo";
          target = "_blank";
        };
      }
    ];
  };

  # Port 80, so the address is just http://xps.
  #
  # homepage-dashboard will not bind a privileged port itself, so something
  # has to sit in front. nginx is the smallest thing that does.
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    virtualHosts."xps" = {
      default = true;
      locations."/".proxyPass = "http://127.0.0.1:8082";
    };
  };

  # Nothing opened to the LAN. nginx still binds 0.0.0.0:80, but only
  # tailscale0 traffic reaches it, by the reasoning above. 22 stays open via
  # services.openssh so there is a way in from the local network if tailscale
  # itself is what broke - key-only, since PasswordAuthentication is off.
  networking.firewall.allowedTCPPorts = [ ];

  # One exception: the living room TV box reaches Jellyfin over the LAN.
  #
  # It has to. Tailscale on that box tops out around 25 Mbit/s - it is a
  # cheap ARM chip doing WireGuard in userspace, and that ceiling held
  # whether it was on wifi or on ethernet. Over the plain LAN the same box
  # sustains 119 Mbit/s, which is what a 98 Mbit/s 4K remux needs. So the
  # tunnel is the bottleneck, not the radio.
  #
  # (Its ethernet port is 100 Mbit and measured *slower* than its wifi, so
  # the cable is not the answer either.)
  #
  # Matched on MAC rather than IP: the address comes from DHCP and moving it
  # would break playback mid-film, while the hardware addresses do not
  # change. Both interfaces are listed - wifi first, then ethernet.
  #
  # This does put a Jellyfin login on the house network, which is the thing
  # closing the firewall was meant to prevent. It is narrowed to one device,
  # but the password should not stay trivial now that this exists.
  networking.firewall.extraCommands = ''
    iptables -I nixos-fw 1 -p tcp --dport 8096 -m mac --mac-source A8:71:16:8B:60:40 -j nixos-fw-accept
    iptables -I nixos-fw 1 -p tcp --dport 8096 -m mac --mac-source 34:D8:56:F9:38:E9 -j nixos-fw-accept
  '';
  networking.firewall.extraStopCommands = ''
    iptables -D nixos-fw -p tcp --dport 8096 -m mac --mac-source A8:71:16:8B:60:40 -j nixos-fw-accept || true
    iptables -D nixos-fw -p tcp --dport 8096 -m mac --mac-source 34:D8:56:F9:38:E9 -j nixos-fw-accept || true
  '';

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

  users.users.xps = {
    isNormalUser = true;
    extraGroups = [ "wheel" "media" "networkmanager" ];

    # A password in the configuration, so a fresh install is never a machine
    # nobody can log into. Three installs in a row left a console that
    # rejected everything, because the only way in was Tailscale SSH and a
    # fresh install has no tailnet identity until somebody authenticates it.
    #
    # initialHashedPassword rather than hashedPassword: it applies when the
    # account is created and `passwd` wins afterwards, so changing it on the
    # machine is not quietly reverted by the next rebuild.
    initialHashedPassword = "$6$nFt5jXC8fDwRPDLn$QIw2F7hsKrwuZNVVbaLDbQvuS3xwg4lTWTS8.JWIOBhNzoK1YoqjsEy7OXhua4sFR5Hh0oHxlns40H6qXYcUt.";

    # Belt and braces for the same problem. Tailscale SSH is the normal way
    # in, and this is what works when tailscaled has nothing to say yet.
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCfo/AgwaTtwll3gj2IH76Ytuehwku/6IRVsoB4coFKHpGI4MQSpiOGObwXA/o9WlgnkyivQ86puWFB6SvN6cqVpVt3ol5g+wxnXUXX3N84stLggjAS6KyfuB3qN7JOFqcHFrLHdO2/6wCSIDjoQJfMJ7V2TMIOPZNXU4hg1gZ6LT8kxK0comu0AI0txax+KO6Q+SudzGrZwKWm0Oi3AU01+l4ItW4dId2DXvzKqhOyspKQYm4F8ZXToFx5kM5kUe3e5mx0Kqd3ryOROlRPSUiiprlL6iQTTCDKRXZ5AhoLpHGIvGVr/AIN1U7l/GcR3KcwK1qCh4VY8ole+PB+5CVQqgnKDW+Z5PL7PtEbiowAgFE5fYWR/acwjFijIxAHss37cr/L8eKTnLp2Psbr0gDRXNHvzUyN3SwPsO1yzslg6NwA1DcnM8hD4nCMd+MT2TeEc+uZafc6mgkV6kJcEgmza0+awVvsUvNWHFI9j5v/8JxnmQEGsIh0UxwN4XOZxJs= jimzer@jimis-macbook-pro.home"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  # What is wanted at the end of an ssh connection, and nothing more. Plain
  # nixpkgs neovim rather than a configured one: this machine is for editing
  # a config file and reading a log, not for living in.
  environment.systemPackages = with pkgs; [
    iw          # so the next person to debug wifi can actually scan
    neovim
    git
    curl
    wget
    htop
    tmux
    rsync
    pciutils
    usbutils
    sqlite      # jellyfin, radarr and sonarr all keep their state in sqlite,
                # and jellyfin has no way to drop a stale row through its API
  ];

  environment.variables.EDITOR = "nvim";

  system.stateVersion = "26.05";
}
