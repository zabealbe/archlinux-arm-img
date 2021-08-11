#!/usr/bin/env bash

set -e
set -x

IMG_DIR="images"
IMG_URL="http://os.archlinuxarm.org/os/${1}.tar.gz"
IMG_NAME=${IMG_URL##*/}
IMG_PATH=${IMG_DIR}/${IMG_NAME}
TARGET_IMAGE=$(basename -s .tar.gz "$IMG_NAME").img
TARGET_ZIP=$(basename -s .tar.gz "$IMG_NAME").zip
TARGET_ZIP_MD5=${TARGET_ZIP}.md5
MD5_URL=${IMG_URL}.md5
MD5_NAME=${MD5_URL##*/}

## Check cache and maybe download
mkdir -p $IMG_DIR
pushd $IMG_DIR
wget -q -N "${MD5_URL}"
if md5sum -c "${MD5_NAME}" ; then
  echo "Cached ${IMG_NAME} already downloaded!"
else
  echo "Cached ${IMG_NAME} did not match MD5 of latest image, downloading"
  wget -q -N "${IMG_URL}"
  # Double check the new version matches
  md5sum -c "${MD5_NAME}"
fi
popd

# Set up image file
truncate -s 1500M "${TARGET_IMAGE}"
LOOP_DEVICE=$(losetup --show --find "${TARGET_IMAGE}") # util-linux v2.21 or higher
parted -s "${LOOP_DEVICE}" mklabel msdos
parted -s "${LOOP_DEVICE}" mkpart primary fat32 -a optimal -- 0% 100MB
parted -s "${LOOP_DEVICE}" set 1 boot on
parted -s "${LOOP_DEVICE}" unit mb mkpart primary ext2 -a optimal -- 100MB 100%
parted -s "${LOOP_DEVICE}" print
mkfs.vfat -I -n SYSTEM "${LOOP_DEVICE}"p1
mkfs.ext4 -F -L root -b 4096 -E stride=4,stripe_width=1024 "${LOOP_DEVICE}"p2

# Mount image
mkdir -p root
mount "${LOOP_DEVICE}"p2 root

# Copy image contents over
bsdtar xfz "${IMG_PATH}" -C root
mv root/boot root/boot-temp
mkdir -p root/boot
mount "${LOOP_DEVICE}"p1 root/boot
mv root/boot-temp/* root/boot/
rm -rf root/boot-temp

# Turn off access time?
sed -i "s/ defaults / defaults,noatime /" root/etc/fstab

# Cleanup
umount root/boot root
losetup -d "${LOOP_DEVICE}"
rm -rf root

# Zip img
zip -r9 --display-dots "${TARGET_ZIP}" "${TARGET_IMAGE}"

# Generate MD5
md5sum "${TARGET_ZIP}" > "${TARGET_ZIP_MD5}"

# Taken from https://gist.github.com/larsch/4ae5499023a3c5e22552
