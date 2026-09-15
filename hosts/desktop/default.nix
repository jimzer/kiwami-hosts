# desktop
#
# Scaffolded by `kiwami install`. Everything here is a choice, not a fact -
# edit it freely, then `nixos-rebuild switch --flake .#desktop`.
#
# hardware.nix beside this file is the facts half, detected at install time.
# Regenerate it with `kiwami doctor` if this machine's hardware changes.
{ config, pkgs, ... }:

{
  imports = [
    # Detected at install time. Do not edit; `kiwami doctor` diffs it against
    # what this machine currently reports.
    ./hardware.nix
    # The layout you chose. disko formats from it and fileSystems is derived
    # from it, so the two cannot drift apart.
    ./disk.nix
  ];

  networking.hostName = "desktop";

  # Where this machine rebuilds itself from. It keeps no checkout, so without
  # this `kiwami update` has nowhere to build and says so.
  #
  # It is the flake this machine was installed from, which is very likely the
  # one you want. Point it at your own configuration repository if you keep
  # your hosts somewhere other than where Kiwami itself lives.
  kiwami.flake = "github:jimzer/kiwami-hosts";

  # The account the desktop belongs to. greetd logs this user in and its home
  # carries the Hyprland and Quickshell config, so a mismatch here is quiet
  # and total: the session comes up on Hyprland's own default config with no
  # bar, because everything was installed for a different account.
  kiwami.user = "kiwami";

  # The root is wiped at every boot; only what kiwami.persist declares
  # survives. disk.nix beside this makes the subvolumes that depend on.
  kiwami.ephemeralRoot = true;

  # Log the desktop user in with no password. Off deliberately: it suits a
  # throwaway VM and not a laptop, where it means whoever opens the lid is
  # you. Uncomment only if you know that is what you want.
  # kiwami.autoLogin = true;

  boot.loader.systemd-boot.enable = true;
  # Without this systemd-boot never registers an NVRAM entry and the firmware
  # boots something else, or nothing.
  boot.loader.efi.canTouchEfiVariables = true;

  # The account itself comes from modules/common.nix, which reads
  # kiwami.user above. The password is not set here: users are immutable, so
  # the hash comes from kiwami.passwordFile, which activation seeds with the
  # default and `kiwami passwd` replaces. Setting initialPassword as well is a
  # conflict Nix only warns about, and the file wins - so the line would look
  # like it set the password while doing nothing.

  # The GTX 1080 Ti.
  #
  # Pascal, which NVIDIA stopped supporting after the 580 branch: 590 and
  # later drop it, so legacy_580 is the last one that drives this card. It is
  # a first-class attribute in nixpkgs, not a pin to some URL, and it builds
  # against the kernel this machine runs - verified rather than assumed, which
  # is why there is no kernel pin here.
  #
  # When a future kernel does break it, the failure is a build error at
  # `kiwami update`, before anything switches. The running system is untouched
  # and the fix is to pin boot.kernelPackages then. A pin now would cost new
  # kernels for years to avoid a problem that announces itself loudly.
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.legacy_580;

    # Required on Wayland, and Kiwami is Hyprland.
    modesetting.enable = true;

    # The open kernel module needs Turing or newer. Pascal predates it, so
    # this must stay false - true builds and then fails to drive the card.
    open = false;
  };
  services.xserver.videoDrivers = [ "nvidia" ];

  # The driver is unfree, and so is Steam below it.
  nixpkgs.config.allowUnfree = true;

  # Steam, and the 32-bit graphics libraries Proton needs.
  #
  # enable32Bit is the line everyone forgets: without it games fail to launch
  # with errors that never mention the missing libraries. Pascal does Vulkan
  # 1.3, which is what DXVK and VKD3D want - no ray tracing or DLSS, since the
  # hardware has neither.
  programs.steam = {
    enable = true;

    # GE-Proton alongside Valve's builds. It carries the media codecs and
    # per-game patches Valve cannot ship, and it is the first thing to switch
    # a stubborn title to - selected per game under Compatibility, so having
    # it installed costs nothing until it is wanted.
    extraCompatPackages = [ pkgs.proton-ge-bin ];

    # Streaming to another device, and moving an installed game over the LAN
    # instead of downloading it twice.
    remotePlay.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
  };
  hardware.graphics.enable32Bit = true;

  # What Steam writes about itself.
  #
  # The client in the store is a launcher and an FHS environment; the real
  # Steam downloads and updates itself into the home directory, the way it
  # does on every distro. That is not a packaging shortcut, it is how Steam
  # works - so unlike neovim, whose plugins moved into Nix precisely to stop
  # it fetching things at runtime, this genuinely is mutable state and has to
  # be kept.
  #
  # 2.5G of it, holding the login, the client itself, and the list of library
  # folders - which is what knows that games live on /games. Without this an
  # ephemeral root discards all three at the next boot: the installed games
  # survive on their own filesystems and Steam no longer knows they are there.
  kiwami.persist.userDirectories = [
    ".local/share/Steam"
    ".steam"
  ];

  # One setting that cannot be made here: Steam Play for titles without
  # native builds is a checkbox in the client, under Settings ->
  # Compatibility -> "Enable Steam Play for all other titles". It lives in
  # Steam's own config, not in Nix, and nothing installed above turns it on.

  # Where games go.
  #
  # Two libraries because the disks differ and the difference is worth
  # keeping: /games is a subvolume of the root filesystem on the Samsung 850
  # EVO, which has a DRAM cache; /games2 is the SanDisk SSD Plus, which is
  # DRAM-less and slower at sustained writes. Unifying them - one btrfs
  # spanning both - would pool the capacity and lose the ability to say which
  # disk a game is on, which is the only reason to have two.
  #
  # Steam handles several library folders natively, and "Move install folder"
  # under a game's Installed Files shifts one between them without
  # re-downloading. /stash is the 10TB, for what does not need to be fast.
  #
  # By label, not by /dev/sdX: the kernel names on this machine shifted
  # between two boots - the Samsung was sda at install time and sdb an hour
  # later - so a layout written in terms of sdX would have formatted the
  # system disk.
  fileSystems."/games" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@games" "compress=zstd" "noatime" ];
  };

  fileSystems."/games2" = {
    device = "/dev/disk/by-label/games2";
    fsType = "ext4";
    options = [ "noatime" "nofail" ];
  };

  fileSystems."/stash" = {
    device = "/dev/disk/by-label/stash";
    fsType = "ext4";
    options = [ "noatime" "nofail" ];
  };

  # nofail on the two data disks and not on /games: the root filesystem is
  # already required to boot, while a missing games disk should not drop the
  # machine into emergency mode over something re-downloadable.

  # The mounts belong to root until told otherwise, and Steam writes as the
  # user. Done with tmpfiles rather than by hand so it survives a reformat
  # and is true on a machine rebuilt from this file alone.
  systemd.tmpfiles.rules = [
    "d /games  0755 ${config.kiwami.user} users - -"
    "d /games2 0755 ${config.kiwami.user} users - -"
    "d /stash  0755 ${config.kiwami.user} users - -"
  ];

  # When this machine was installed. Kiwami applies the desktop user's home
  # configuration itself; this is the one part of it that belongs to the
  # machine rather than to the distro.
  home-manager.users.kiwami.home.stateVersion = "26.05";

  system.stateVersion = "26.05";
}
