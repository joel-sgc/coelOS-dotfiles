{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.filesystemSupport;
in
{
  ##############################################################################
  # Cross-platform filesystem support (HFS+ / APFS / NTFS / exFAT)
  #
  # Split into two independent layers per filesystem:
  #   - Kernel-level read/write mount support: always on, never toggled here.
  #     NTFS/HFS+/exFAT are mainline Linux drivers (auto-load on mount, no
  #     config needed); APFS needs the out-of-tree linux-apfs-rw module,
  #     wired up unconditionally below via boot.kernelModules /
  #     boot.extraModulePackages.
  #   - Userspace "extra tools" (mkfs.*, fsck.*, and apfs-fuse's read-only
  #     fallback + volume listing): toggleable per filesystem group via the
  #     options below. Disabling a group only removes these convenience
  #     packages -- mounting/reading/writing an existing volume of that type
  #     keeps working regardless, since that's the kernel driver's job, not
  #     these tools'.
  ##############################################################################

  options.filesystemSupport = {
    ntfs.extraTools = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Install ntfs3g (mkfs.ntfs/mkntfs, ntfsfix, ntfsresize). The ntfs3
        kernel driver (actual read/write mount support) is mainline and
        stays available regardless of this option.
      '';
    };

    hfs.extraTools = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Install hfsprogs (mkfs.hfsplus, fsck.hfsplus). The hfsplus kernel
        driver (actual read/write mount support) is mainline and stays
        available regardless of this option.
      '';
    };

    apfs.extraTools = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Install apfsprogs (mkfs.apfs, fsck.apfs -- experimental) and
        apfs-fuse (read-only fallback + `apfs-fuse -l` volume listing). The
        apfs kernel module itself -- the actual read/write mount capability
        -- is wired up unconditionally below and is unaffected by this
        option.
      '';
    };

    exfat.extraTools = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Install exfatprogs (mkfs.exfat, fsck.exfat). The exfat kernel
        driver (actual read/write mount support) is mainline and stays
        available regardless of this option. Defaults off since NTFS is
        the cross-platform format currently in use.
      '';
    };
  };

  config = {
    # Kernel-level support -- unconditional. HFS+ needs nothing extra
    # (mainline, auto-loads on mount); APFS needs the out-of-tree module
    # explicitly listed and built.
    #
    # HFS+: most macOS-formatted volumes are journaled; if one wasn't
    # cleanly unmounted from a Mac, the kernel driver refuses an rw mount
    # unless told to bypass that safety check:
    #   mount -t hfsplus -o rw,force /dev/sdXN /mnt/whatever
    #
    # APFS: write support is real but explicitly marked experimental/
    # dangerous upstream (linux-apfs-rw), so keep backups. No encrypted-
    # volume (FileVault) support either. A single physical partition is
    # usually an APFS *container* holding multiple logical *volumes* (e.g.
    # modern macOS's own "Macintosh HD" + "Macintosh HD - Data" split) --
    # `apfs-fuse -l` lists them, and a specific one is picked with
    # `mount -t apfs -o vol=N ...`.
    boot.kernelModules = [ "hfsplus" "apfs" ];
    boot.extraModulePackages = [ config.boot.kernelPackages.apfs ];

    environment.systemPackages = with pkgs;
      optional cfg.ntfs.extraTools ntfs3g
      ++ optional cfg.hfs.extraTools hfsprogs
      ++ optionals cfg.apfs.extraTools [ apfsprogs apfs-fuse ]
      ++ optional cfg.exfat.extraTools exfatprogs;
  };
}
