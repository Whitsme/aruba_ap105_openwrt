#!/bin/bash

# Prompt the user to input the serial number
read -p "Enter the AP105 serial number: " serial_number

# Create the directory structure with the user-input serial number
mkdir -p "/aruba_ap105/$serial_number"
cd "/aruba_ap105/$serial_number"

# Dump the stock SPI flash contents using flashrom utility
flashrom -r AP105-stock-SPI-dump.rom -p ft2232_spi:type=232H,divisor=4 -V -c MX25L12835F/MX25L12845E/MX25L12865E 

# Create a backup of the stock SPI dump
cp ./AP105-stock-SPI-dump.rom ./custom-dump.rom 

# Overwrite the first 256K bytes of the backup file with FF bytes
dd if=/dev/zero bs=256K count=1 | tr "\000" "\377" | dd of=custom-dump.rom conv=notrunc  

# Used bs=1 count=65536 seek=262144 with the dd command to ensure that only the first 64K bytes are overwritten with the u-boot binary.
dd if=../u-boot.bin of=custom-dump.rom conv=notrunc bs=1 count=65536 seek=262144

# Write the modified SPI dump back to the flash memory
flashrom -w custom-dump.rom -p ft2232_spi:type=232H,divisor=4 -V -c MX25L12835F/MX25L12845E/MX25L12865E 

# Clean up and print the completion message
cd ..
echo "Done! Please remove the USB cable, reassemble the AP105, and connect a console cable, ethernet, and power (or POE) to the AP105 for downloading the new firmware."

if ! dpkg -s tftpd-hpa >/dev/null 2>&1; then
    sudo apt update
    sudo apt upgrade
    sudo apt install -y tftpd-hpa
fi

# Start the tftp server and copy the firmware to the server directory
sudo systemctl start tftpd-hpa
cp ./firmware.bin /srv/tftp/firmware.bin

# Save the current networking configuration
OLD_CONFIG=$(nmcli networking)

# Set the IP address for eth0 to 192.168.1.101
nmcli connection modify eth0 ipv4.addresses 192.168.1.101/24 ipv4.method manual

# Show the IP address of eth0
nmcli connection show eth0 | grep "IP4.ADDRESS"

MAX_TRIES=5
SLEEP_TIME=5

for i in $(seq 1 $MAX_TRIES); do
    # Check if Ethernet connection is active
    if ifconfig eth0 | grep -q "inet "; then
        for i in $(seq 1 $MAX_TRIES); do
            # tries to ping the ap105
            ping -c 1 -w 2 192.168.1.2 >/dev/null 2>&1 &
            if [ $? -eq 0 ]; then
                busybox tftp -l /srv/tftp/firmware.bin -p 192.168.1.2 > /dev/null 2>&1 &  

            fi
        done
        break
    fi
done

for i in $(seq 1 $MAX_TRIES); do
    # Check if ttyUSB0 is available
    if [ ! -c "/dev/ttyUSB0" ]; then
        echo "ttyUSB0 is not available. Please connect ttyUSB0 and try again."
    else
        echo "ttyUSB0 is available. Continuing with the script..."
        # Set up the serial connection
        USB_DEVICE_NAME="ttyUSB0"
        BAUD_RATE="9600"
        stty -F /dev/$USB_DEVICE_NAME $BAUD_RATE cs8 -cstopb -parity

        # Read the output from the serial device and prompt the user to continue if needed
        while read LINE; do
        if [ $(echo "$LINE" | cut -c 1-6) -gt 74 ]; then
            read -p "Press Enter to continue..."
        fi
        done < /dev/$USB_DEVICE_NAME
        break
    fi

# Revert the networking configuration back to its original state
nmcli networking off && nmcli networking on && nmcli networking connect $OLD_CONFIG





