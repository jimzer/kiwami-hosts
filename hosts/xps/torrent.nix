# A torrent client that cannot reach the internet except through Proton.
#
# Usenet needed none of this: it is a private TLS pull from one provider, and
# nobody but that provider learns what was fetched. Torrents are the opposite
# - the indexers reachable here are public trackers, so every peer in the
# swarm and every monitoring firm watching it sees the address that asked.
# On a home line in Europe that is how the letters start.
#
# So qBittorrent runs inside a network namespace: its own routing table, its
# own interfaces, its own firewall. A fresh namespace contains nothing at all
# - no default route, no addresses - and the only route added is the Proton
# WireGuard tunnel. This is not a kill switch watching for a dead tunnel and
# reacting; there is simply no path to the house network to leak through. If
# the tunnel drops, packets have nowhere to go and transfers stall.
#
# Only networking is separated. The process still sees /stash and /staging
# as any other service does.
#
# vpn-confinement builds the namespace, the tunnel and the veth pair that
# bridges it back to the host. Hand-rolling it is about fifty lines of
# systemd, and the two traps in it are not obvious: a bare namespace falls
# back to the host's resolver, so the traffic goes through Proton while the
# DNS lookups do not, and the tunnel MTU has to be right or TLS inside the
# namespace stalls rather than fails. Both are handled upstream.
{ config, lib, ... }:

{
  # The namespace. The name is limited to seven characters by the module.
  #
  # It gets 192.168.15.1 inside, and the host end of the veth is
  # 192.168.15.5 - so "localhost" is not how anything here talks to
  # qBittorrent, which is why the bind address below is spelled out.
  vpnNamespaces.vpn = {
    enable = true;

    # Generated in the Proton web interface, not by their Linux app, and
    # written on the machine rather than committed. Same reasoning as the
    # servarr keys: /var/lib/secrets persists because there is no
    # impermanence here, and the nix store is world readable.
    #
    # It must be a P2P server - Proton only permits peer-to-peer on those,
    # and the file is per-server.
    wireguardConfigFile = "/var/lib/secrets/proton.conf";

    # Who may reach into the namespace. The tailnet is the real answer;
    # 100.64.0.0/10 is the range tailscale assigns. The LAN is here because
    # the firewall already refuses it, so this grants nothing on its own and
    # saves a confusing second edit if that ever changes.
    #
    # The veth subnet 192.168.15.0/24 is deliberately absent. Each entry
    # becomes a route via the bridge, and that one is already connected -
    # the namespace end of the veth holds 192.168.15.1/24. Adding it fails
    # with "RTNETLINK answers: File exists", and the script runs under
    # errexit, so the whole namespace fails to come up. The host reaches the
    # client over that subnet regardless; it needs no route to do it.
    accessibleFrom = [
      "100.64.0.0/10"
      "192.168.1.0/24"
    ];

    # Host port to namespace port, so radarr and sonarr - which live in the
    # default namespace - can drive the client over the veth.
    portMappings = [
      { from = 8090; to = 8090; }
    ];

    # Deliberately no openVPNPorts.
    #
    # That option forwards a port in through the tunnel, which is what
    # seeding needs: peers have to be able to start a connection. Nothing
    # here seeds, so there is nothing to accept, and leaving it out skips
    # the whole of Proton's port forwarding - NAT-PMP at config generation
    # time plus a loop renewing the mapping every sixty seconds because it
    # expires, and a port that changes on every reconnect. Downloads are
    # unaffected: qBittorrent dials out to peers and gets full speed from
    # a slightly smaller pool.
  };

  systemd.services.qbittorrent.vpnConfinement = {
    enable = true;
    vpnNamespace = "vpn";
  };

  services.qbittorrent = {
    enable = true;

    # 8080 is sabnzbd's. The module's default would collide silently.
    webuiPort = 8090;

    # Not openFirewall, for the reason jellyfin is not: tailscale accepts
    # its own traffic before the NixOS firewall is consulted, so closing
    # the port shuts out the LAN and changes nothing for the tailnet.
    openFirewall = false;

    serverConfig = {
      Preferences = {
        # The namespace address, not 0.0.0.0. Inside the namespace there is
        # no other interface to bind, and the host reaches it here.
        "WebUI\\Address" = "192.168.15.1";

        # radarr and sonarr arrive from the host end of the veth and are
        # trusted without a password; anything from the tailnet still needs
        # one. The alternative is storing a PBKDF2 hash of a web password
        # in the store, which is worse for no gain.
        "WebUI\\AuthSubnetWhitelistEnabled" = true;
        "WebUI\\AuthSubnetWhitelist" = "192.168.15.0/24";

        # The WebUI refuses a Host header it does not recognise, which is
        # every name this is actually reached by.
        "WebUI\\HostHeaderValidation" = false;
      };

      BitTorrent = {
        # Finished torrents and partial ones, both on the media drive -
        # 476G of root would otherwise fill up behind one season.
        "Session\\DefaultSavePath" = "/stash/Torrents";
        "Session\\TempPath" = "/stash/Torrents/.incomplete";
        "Session\\TempPathEnabled" = true;

        # Stop at ratio zero: that is, the moment it finishes.
        #
        # ShareLimitAction is left at its default of Stop rather than set to
        # RemoveWithContent, which would be the obvious way to say "throw it
        # away". It would race the import - qBittorrent would delete the file
        # while radarr was still copying it. So the client stops seeding and
        # keeps the data, and whichever of radarr or sonarr asked for it
        # removes both once the copy has landed.
        "Session\\GlobalMaxRatio" = 0;
      };
    };
  };

  # exFAT has no permissions of its own; everything on /stash takes the gid
  # given at mount time, and services join that group rather than chowning.
  users.users.qbittorrent.extraGroups = [ "media" ];

  # ...which only works if the group survives into the service.
  #
  # The upstream module hardens the unit with PrivateUsers, and that is the
  # one setting here that cannot stay. It runs the service in a user
  # namespace mapping only its own uid and gid; a supplementary group from
  # outside that map - media, gid 985 - arrives as the overflow gid instead.
  # /stash is root:media and group-writable, so qBittorrent would match
  # neither owner nor group and every write would be refused. The failure is
  # a permissions error on a drive that looks mounted and fine.
  #
  # So PrivateUsers is off and the group is named in the unit as well as on
  # the user, which is what actually puts it in the credentials. The rest of
  # the sandbox - the syscall filter, the read-only system, the namespace
  # itself - is untouched.
  systemd.services.qbittorrent.serviceConfig = {
    PrivateUsers = lib.mkForce false;
    SupplementaryGroups = [ config.users.groups.media.name ];
  };

  # The save paths, created before the service wants them. 775 so the media
  # group can write, matching the drive's umask - on exfat the mount decides
  # anyway, but /stash may not be mounted and then these land on root.
  systemd.tmpfiles.rules = [
    "d /stash/Torrents             0775 root ${config.users.groups.media.name} -"
    "d /stash/Torrents/.incomplete 0775 root ${config.users.groups.media.name} -"
  ];

  # A client whose downloads are unreachable is worse than one that does not
  # start, because the first looks like it is working. If /stash is not
  # mounted, do not run.
  systemd.services.qbittorrent.unitConfig.RequiresMountsFor = "/stash";
}
