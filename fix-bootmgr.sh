#!/bin/bash

efibootmgr --create --disk /dev/nvme0n1 --part 1 --label "CoelOS" --loader '\EFI\arch-limine\BOOTX64.EFI'