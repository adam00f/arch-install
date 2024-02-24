#!/bin/bash

# Set the time zone
timedatectl set-timezone America/Los_Angeles

# Define the disk to partition
DISK=/dev/sda

# Confirm execution
echo "WARNING: This will erase all data on $DISK and create new partitions."
read -p "Are you sure you want to continue? (y/n) " choice
case "$choice" in 
  y|Y ) echo "Proceeding with partitioning...";;
  n|N ) echo "Operation cancelled."; exit;;
  * ) echo "Invalid response."; exit;;
esac

# Step 1: Partition the disk
# Clear the disk and create GPT, EFI (1G), swap (size as needed, e.g., 6G here), and Linux partitions
echo -e "o\nY\nn\n\n\n+1G\nef00\nn\n\n\n+6G\n8200\nn\n\n\n\n8300\nw\nY\n" | gdisk $DISK

# Step 2: Format the EFI and Linux partitions
mkfs.fat -F32 ${DISK}1  # EFI partition
mkfs.btrfs -L arch ${DISK}3  # Linux partition with Btrfs

# Step 3: Mount and create Btrfs subvolumes
mount ${DISK}3 /mnt
cd /mnt
btrfs subvolume create _active
btrfs subvolume create _active/rootvol
btrfs subvolume create _active/homevol
btrfs subvolume create _snapshots
cd ..
umount /mnt

# Step 4: Mount the subvolumes and create directories
mount -o subvol=_active/rootvol ${DISK}3 /mnt
mkdir -p /mnt/{home,boot,boot/efi,mnt/defvol}
mount ${DISK}1 /mnt/boot/efi
mount -o subvol=_active/homevol ${DISK}3 /mnt/home
mount -o subvol=/ ${DISK}3 /mnt/mnt/defvol

echo "Partitioning and Btrfs setup complete."

# Initialize and populate pacman keys
pacman-key --init
pacman-key --populate

# Refresh the package databases
pacman -Syy

# Install reflector
pacman -S --noconfirm reflector

# Configure reflector to optimize the mirror list
reflector --verbose -l 200 -n 20 -p https --sort rate --save /etc/pacman.d/mirrorlist

echo "Pacman keys initialized, package databases refreshed, and mirror list optimized."

# Install the base system, kernel, and essential packages
pacstrap -K /mnt base linux linux-firmware vim sudo git curl networkmanager wget grub efibootmgr

echo "Base system and essential packages have been installed."

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the new system
arch-chroot /mnt /bin/bash <<EOF

# Set the time zone
ln -sf /usr/share/zoneinfo/America/Los_Angeles /etc/localtime

# Generate /etc/adjtime
hwclock --systohc

# Install Btrfs-related packages
pacman -S --noconfirm btrfs-progs grub-btrfs

EOF

echo "System configuration tasks have been completed."
