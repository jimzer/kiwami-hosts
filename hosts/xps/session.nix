# A graphical session on the xps, for when it is the only machine in the room.
#
# default.nix calls this machine headless and that is still what it is for:
# nothing here starts on its own, there is no greeter, and with the lid shut
# the box runs none of it. The session exists when somebody logs in at the
# console and types `Hyprland`, and ends when they exit it.
#
# Why Hyprland and not the kiosk this started as: a single fullscreen browser
# cannot have a terminal beside it, and the moment that is wanted the kiosk is
# the wrong tool. This is a real compositor with workspaces and keybindings.
#
# It is NOT the desktop machine's Hyprland. That one is configured by Kiwami,
# and flake.nix is explicit that no Kiwami input reaches this host - the point
# being that the xps can be rebuilt or handed over without the distro
# existing. So the config below is a small standalone one written here, and
# the keybindings are deliberately plain rather than a guess at matching the
# desktop's muscle memory.
#
# This file is the whole feature. Dropping it from the imports in default.nix
# removes the compositor, the browser, the fonts and the sound stack together
# and leaves a headless media server behind.
{ pkgs, ... }:

{
  # Pulls in the compositor, its portal, and XWayland. XWayland stays on
  # deliberately: it costs nothing when unused and is the difference between
  # an old X11-only tool working and not.
  programs.hyprland.enable = true;

  # hardware.graphics is already enabled in default.nix for Jellyfin's
  # transcoding, so the GL and VA-API userspace is present. Nothing about the
  # GPU needs adding here.
  environment.systemPackages = with pkgs; [
    brave
    foot            # Wayland-native, starts instantly, no config needed
    wofi            # SUPER+D, so launching something is not a shell exercise
    wl-clipboard    # without this copy/paste between apps silently does nothing
    brightnessctl   # the laptop's own keys, bound below
    grim
    slurp           # grim+slurp is screenshot-a-region
  ];

  # What makes Chromium pick Wayland rather than X11. Without it Brave runs
  # through XWayland, which works but renders blurry under any scaling and
  # loses native clipboard and input handling. Set for the whole system
  # rather than in a wrapper so Electron apps get it too; it affects nothing
  # on a machine with no display server running.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # video and render for the console user: logind hands the active seat an
  # ACL on the card, but not on renderD128, so hardware video decode in the
  # browser needs the group. Harmless when nobody is logged in.
  users.users.xps.extraGroups = [ "video" "render" ];

  # The config, in /etc rather than a home directory.
  #
  # This machine has no home-manager, and a dotfile copied into ~ by hand is
  # exactly the kind of state that survives a reinstall by accident or not at
  # all. Hyprland reads $XDG_CONFIG_DIRS after the user's own config, so a
  # file here is the default for every account and can still be overridden by
  # dropping one in ~/.config/hypr.
  environment.etc."xdg/hypr/hyprland.conf".text = ''
    # The laptop panel. Written down because Hyprland picking a mode on its
    # own is how the desktop machine ended up running at 40% of its refresh.
    monitor = eDP-1, 1920x1080@60, 0x0, 1

    $mod = SUPER

    bind = $mod, Return, exec, ${pkgs.foot}/bin/foot
    bind = $mod, B, exec, ${pkgs.brave}/bin/brave
    bind = $mod, D, exec, ${pkgs.wofi}/bin/wofi --show drun
    bind = $mod, Q, killactive
    bind = $mod, F, fullscreen, 0
    bind = $mod, V, togglefloating
    bind = $mod SHIFT, E, exit

    # Screenshot a region to the clipboard.
    bind = $mod SHIFT, S, exec, ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" - | ${pkgs.wl-clipboard}/bin/wl-copy

    bind = $mod, left,  movefocus, l
    bind = $mod, right, movefocus, r
    bind = $mod, up,    movefocus, u
    bind = $mod, down,  movefocus, d

    bind = $mod, 1, workspace, 1
    bind = $mod, 2, workspace, 2
    bind = $mod, 3, workspace, 3
    bind = $mod, 4, workspace, 4
    bind = $mod SHIFT, 1, movetoworkspace, 1
    bind = $mod SHIFT, 2, movetoworkspace, 2
    bind = $mod SHIFT, 3, movetoworkspace, 3
    bind = $mod SHIFT, 4, movetoworkspace, 4

    bindm = $mod, mouse:272, movewindow
    bindm = $mod, mouse:273, resizewindow

    # The laptop's own keys. bindel repeats while held, which is what makes
    # holding brightness-up ramp rather than step once.
    bindel = , XF86MonBrightnessUp,   exec, ${pkgs.brightnessctl}/bin/brightnessctl set +5%
    bindel = , XF86MonBrightnessDown, exec, ${pkgs.brightnessctl}/bin/brightnessctl set 5%-
    bindel = , XF86AudioRaiseVolume,  exec, ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
    bindel = , XF86AudioLowerVolume,  exec, ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
    bindl  = , XF86AudioMute,         exec, ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle

    input {
      kb_layout = us
      touchpad {
        natural_scroll = true
        tap-to-click = true
      }
    }

    general {
      gaps_in = 4
      gaps_out = 8
      border_size = 2
    }

    decoration {
      rounding = 6
    }

    misc {
      disable_hyprland_logo = true
      disable_splash_rendering = true
    }
  '';

  # Web pages assume fonts exist. Without these every page renders as empty
  # boxes, which reads as a broken browser rather than a missing dependency.
  # liberation_ttf is here for the metric-compatible Arial and Times
  # substitutes, which is what stops layouts collapsing on sites that ask for
  # those by name.
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-color-emoji
      dejavu_fonts
      liberation_ttf
    ];
  };

  # Sound, so a video in the browser has some.
  #
  # pipewire's daemons are user services, so they start with a login and are
  # absent the rest of the time. Nothing else on this box competes for the
  # device: Jellyfin never plays audio locally, it streams it.
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
}
