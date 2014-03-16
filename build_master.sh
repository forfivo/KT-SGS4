#!/bin/sh
export PLATFORM="TW"
export MREV="KK4.4"
export CURDATE=`date "+%m.%d.%Y"`
export MUXEDNAMELONG="KT-SGS4-$MREV-$PLATFORM-$CARRIER-$CURDATE"
export MUXEDNAMESHRT="KT-SGS4-$MREV-$PLATFORM-$CARRIER*"
export KTVER="--$MUXEDNAMELONG--"
export KERNELDIR=`readlink -f .`
export PARENT_DIR=`readlink -f ..`
export INITRAMFS_DEST=$KERNELDIR/kernel/usr/initramfs
export INITRAMFS_SOURCE=`readlink -f ..`/ramdisk-kt
export CONFIG_$PLATFORM_BUILD=y
export PACKAGEDIR=$PARENT_DIR/Packages/$PLATFORM
#Enable FIPS mode
export USE_SEC_FIPS_MODE=true
export ARCH=arm
export KERNEL_CONFIG=KT_jf_defconfig;
export CROSS_COMPILE=$PARENT_DIR/linaro_toolchains_2014/arm-cortex_a15-linux-gnueabihf-linaro_4.8.3-2014.03/bin/arm-cortex_a15-linux-gnueabihf-

time_start=$(date +%s.%N)

echo "Remove old Package Files"
rm -rf $PACKAGEDIR/*

echo "Setup Package Directory"
mkdir -p $PACKAGEDIR/system/app
mkdir -p $PACKAGEDIR/system/lib/modules
mkdir -p $PACKAGEDIR/system/etc/init.d

echo "Create initramfs dir"
mkdir -p $INITRAMFS_DEST

# copy new config
cp $KERNELDIR/.config $KERNELDIR/arch/arm/configs/$KERNEL_CONFIG;

# remove all old modules before compile
for i in `find $KERNELDIR/ -name "*.ko"`; do
	rm -f $i;
done;
for i in `find $PACKAGEDIR/system/lib/modules/ -name "*.ko"`; do
	rm -f $i;
done;

echo "Remove old initramfs dir"
rm -rf $INITRAMFS_DEST/*

echo "Copy new initramfs dir"
cp -R $INITRAMFS_SOURCE/* $INITRAMFS_DEST

echo "chmod initramfs dir"
chmod -R g-w $INITRAMFS_DEST/*
rm $(find $INITRAMFS_DEST -name EMPTY_DIRECTORY -print)
rm -rf $(find $INITRAMFS_DEST -name .git -print)

echo "Remove old zImage"
rm $PACKAGEDIR/zImage
rm arch/arm/boot/zImage

echo "Make the kernel"
make VARIANT_DEFCONFIG=jf_$CARRIER"_defconfig" $KERNEL_CONFIG SELINUX_DEFCONFIG=selinux_defconfig

# copy config
if [ ! -f $KERNELDIR/.config ]; then
	cp $KERNELDIR/arch/arm/configs/$KERNEL_CONFIG $KERNELDIR/.config;
fi;

# read config
. $KERNELDIR/.config;

echo "Modding .config file - "$KTVER
sed -i 's,CONFIG_LOCALVERSION="-KT-SGS4",CONFIG_LOCALVERSION="'$KTVER'",' .config


echo "Copy modules to Package"
cp -a $(find . -name *.ko -print |grep -v initramfs) $PACKAGEDIR/system/lib/modules/
if [ $ADD_KTWEAKER = 'Y' ]; then
	cp /home/ktoonsez/workspace/com.ktoonsez.KTweaker.apk $PACKAGEDIR/system/app/com.ktoonsez.KTweaker.apk
	cp /home/ktoonsez/workspace/com.ktoonsez.KTmonitor.apk $PACKAGEDIR/system/app/com.ktoonsez.KTmonitor.apk
fi;

echo "Remove old zImage"
# remove previous zImage files
if [ -e $PACKAGEDIR/boot.img ]; then
	rm $PACKAGEDIR/boot.img;
fi;

if [ -e $KERNELDIR/arch/arm/boot/zImage ]; then
	rm $KERNELDIR/arch/arm/boot/zImage;
fi;

HOST_CHECK=`uname -n`
NAMBEROFCPUS=$(expr `grep processor /proc/cpuinfo | wc -l` + 1);
echo $HOST_CHECK

echo "Making kernel";
make -j${NAMBEROFCPUS} || exit 1;

echo "Copy modules to Package"
for i in `find $KERNELDIR -name '*.ko'`; do
	cp -av $i $PACKAGEDIR/system/lib/modules/;
done;

for i in `find $PACKAGEDIR/system/lib/modules/ -name '*.ko'`; do
	${CROSS_COMPILE}strip --strip-unneeded $i;
done;

chmod 644 $PACKAGEDIR/system/lib/modules/*;

if [ -e $KERNELDIR/arch/arm/boot/zImage ]; then
	echo "Copy zImage to Package"
	cp arch/arm/boot/zImage $PACKAGEDIR/zImage

	echo "Make boot.img"
	./mkbootfs $INITRAMFS_DEST | gzip > $PACKAGEDIR/ramdisk.gz
	./mkbootimg --cmdline 'console=null androidboot.hardware=qcom user_debug=31 msm_rtb.filter=0x3F ehci-hcd.park=3 maxcpus=4' --kernel $PACKAGEDIR/zImage --ramdisk $PACKAGEDIR/ramdisk.gz --base 0x80200000 --pagesize 2048 --ramdisk_offset 0x02000000 --output $PACKAGEDIR/boot.img 
	cd $PACKAGEDIR
	if [ $EXEC_LOKI = 'Y' ]; then
		cp -R ../META-INF-SEC ./META-INF
	else
		cp -R ../META-INF .
	fi;

	if [ -e ramdisk.gz ]; then
		rm ramdisk.gz;
	fi;

	if [ -e zImage ]; then
		rm zImage;
	fi;
	rm ../$MUXEDNAMESHRT.zip
	zip -r ../$MUXEDNAMELONG.zip .

	time_end=$(date +%s.%N)
	echo -e "${BLDYLW}Total time elapsed: ${TCTCLR}${TXTGRN}$(echo "($time_end - $time_start) / 60"|bc ) ${TXTYLW}minutes${TXTGRN} ($(echo "$time_end - $time_start"|bc ) ${TXTYLW}seconds) ${TXTCLR}"

	export DLNAME="http://ktoonsez.jonathanjsimon.com/sgs4/$PLATFORM/$MUXEDNAMELONG.zip"
	
	FILENAME=../$MUXEDNAMELONG.zip
	FILESIZE=$(stat -c%s "$FILENAME")
	echo "Size of $FILENAME = $FILESIZE bytes."
	rm ../$MREV-$PLATFORM-$CARRIER"-version.txt"
	exec 1>>../$MREV-$PLATFORM-$CARRIER"-version.txt" 2>&1
	echo -n "$MUXEDNAMELONG,$FILESIZE," & curl -s https://www.googleapis.com/urlshortener/v1/url --header 'Content-Type: application/json' --data "{'longUrl': '$DLNAME'}" | grep \"id\" | sed -e 's,^.*id": ",,' -e 's/",.*$//'
	echo 1>&-
	
	SHORTURL=$(grep "http" ../$MREV-$PLATFORM-$CARRIER"-version.txt" | sed s/$MUXEDNAMELONG,$FILESIZE,//g)
	exec 1>>../url/aurlstats-$CURDATE.sh 2>&1
	##echo "curl -s 'https://www.googleapis.com/urlshortener/v1/url?shortUrl="$SHORTURL"&projection=FULL' | grep -m2 \"shortUrlClicks\|\\\"longUrl\\\"\""
	echo "echo "$MREV-$PLATFORM-$CARRIER
	echo "curl -s 'https://www.googleapis.com/urlshortener/v1/url?shortUrl="$SHORTURL"&projection=FULL' | grep -m1 \"shortUrlClicks\""
	echo 1>&-
	chmod 0777 ../url/aurlstats-$CURDATE.sh
	sed -i 's,http://ktoonsez.jonathanjsimon.com/sgs4/'$PLATFORM'/'$MUXEDNAMESHRT','"[B]"$CURDATE":[/B] [url]"$SHORTURL'[/url],' ../url/SERVERLINKS.txt

	cd $KERNELDIR
else
	echo "KERNEL DID NOT BUILD! no zImage exist"
fi;
