# My machines.
#
# They are not all the same kind of thing any more, and this file says so
# rather than hiding it.
#
# `desktop` is a Kiwami machine: it imports the distro and gets a desktop,
# a shell, themes and the rest from one import.
#
# `xps` is plain NixOS. It stopped being a laptop and became a media server,
# and almost nothing Kiwami provides is wanted on a headless box - so it
# takes nixpkgs directly and declares the handful of services it runs.
#
# The host list used to be a directory listing, which was neat while every
# machine was built the same way. It is written out now because they are not,
# and a machine's builder is worth seeing.
{
  description = "jimzer's machines";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    kiwami.url = "github:kiwamios/kiwami";

    # Partitions from hosts/<name>/disk.nix. nixos-anywhere reads the same
    # module to format a machine before installing it, which is why the
    # layout lives in the repository rather than in an installer.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # qBittorrent runs in a network namespace whose only route out is a
    # WireGuard tunnel, so torrent traffic cannot take the house line. The
    # module builds the namespace, the tunnel and the veth back to the host,
    # and handles the two things that are easy to get wrong by hand: the
    # resolver inside the namespace, and the tunnel MTU.
    vpn-confinement.url = "github:Maroka-chan/VPN-Confinement";
  };

  outputs = { self, nixpkgs, kiwami, disko, vpn-confinement, ... }:
    {
      nixosConfigurations = {
        # The distro's own machine.
        desktop = kiwami.lib.mkHost [ ./hosts/desktop ];

        # Plain NixOS. No Kiwami input reaches this one at all, which is the
        # point: it can be rebuilt, reinstalled or handed over without the
        # distro existing.
        xps = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            disko.nixosModules.disko
            vpn-confinement.nixosModules.default
            ./hosts/xps
          ];
        };
      };
    };
}
