# desktop
#
# Scaffolded by `kiwami install`. Everything here is a choice, not a fact -
# edit it freely, then `nixos-rebuild switch --flake .#desktop`.
#
# hardware.nix beside this file is the facts half, detected at install time.
# Regenerate it with `kiwami doctor` if this machine's hardware changes.
{ config, ... }:

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
  programs.steam.enable = true;
  hardware.graphics.enable32Bit = true;

  # When this machine was installed. Kiwami applies the desktop user's home
  # configuration itself; this is the one part of it that belongs to the
  # machine rather than to the distro.
  home-manager.users.kiwami.home.stateVersion = "26.05";

  system.stateVersion = "26.05";
}
