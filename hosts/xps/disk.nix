# The XPS's disk, as disko describes it.
#
# Read by nixos-anywhere, which partitions and formats from this before
# installing. It is the whole layout: one EFI partition and one root, no
# encryption and no subvolume games.
#
# No LUKS, deliberately. This machine is a headless server that must come
# back from a power cut on its own, and an encrypted root means it sits at a
# passphrase prompt until somebody walks over to it. The trade is that the
# disk is readable if the laptop is stolen, which is why nothing private
# lives on it.
{
  disko.devices.disk.main = {
    device = "/dev/disk/by-id/nvme-PM981_NVMe_Samsung_512GB__S3ZHNA0M640707";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
