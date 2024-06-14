#!/bin/bash -e
# -----------------------------------------------------------------------------
#
# Package	: {package_name}
# Version	: {package_version}
# Source repo	: {package_url}
# Tested on	: {distro_name} {distro_version}
# Language      : Conda
# Travis-Check  : True
# Script License: Apache License, Version 2 or later
# Maintainer	: BulkPackageSearch Automation {maintainer}
#
# Disclaimer: This script has been tested in root mode on given
# ==========  platform using the mentioned version of the package.
#             It may not work as expected with newer versions of the
#             package and/or distribution. In such case, please
#             contact "Maintainer" of this script.
#
# ----------------------------------------------------------------------------

set -e

# Parse named parameters
while [[ "$#" -gt 0 ]]; do
   case $1 in
       -u|--url) PACKAGE_URL="$2"; shift ;;
       -n|--name) PACKAGE_NAME="$2"; shift ;;
       -v|--version) PACKAGE_VERSION="$2"; shift ;;
       *) echo "Unknown parameter passed: $1"; exit 1 ;;
   esac
   shift
done

yum install -y git wget

# miniconda installation 
wget https://repo.anaconda.com/miniconda/Miniconda3-py311_23.10.0-1-Linux-ppc64le.sh -O miniconda.sh 
bash miniconda.sh -b -p $HOME/miniconda
export PATH="$HOME/miniconda/bin:$PATH"
conda create -n $PACKAGE_NAME python=3.11 -y
eval "$(conda shell.bash hook)"
conda activate $PACKAGE_NAME

conda install -y conda-build conda-verify

#clone repository 
git clone $PACKAGE_URL

#get the source url from meta.yaml
url=$(sed -n '/^\s*url:/s/^\s*url:\s*\(.*\)$/\1/p' /${PACKAGE_NAME}-feedstock/recipe/meta.yaml)

# Check if the URL contains only {{ version }} or both {{ version }} and {{ name }}
if [[ "$url" == *"{{ version }}"* && "$url" == *"{{ name }}"* ]]; then
   # replace square brackets with circular brackets in url
   url=$(echo "$url" | sed 's/\[/(/g; s/\]/)/g')
   # Modify the URL replacing {{ name(0) }} and {{ name }} placeholders
   modified_url=$(echo "$url" | sed -e "s/{{ version }}/$PACKAGE_VERSION/g" -e "s/{{ name(0) }}/${PACKAGE_NAME:0:1}/g" -e "s/{{ name }}/${PACKAGE_NAME}/g")
else
   # Modify the URL replacing only {{ version }} placeholder
   modified_url=$(echo "$url" | sed "s/{{ version }}/$PACKAGE_VERSION/g")
fi

wget -O "$PACKAGE_NAME.tar.gz" $modified_url

#generating sha256 for required version
checksum=$(sha256sum $PACKAGE_NAME.tar.gz | awk '{print $1}')

#replace version and sha256 value with required version values
sed -i "/{% set version =/c\{% set version = \"$PACKAGE_VERSION\" %}" "${PACKAGE_NAME}-feedstock/recipe/meta.yaml"
sed -i "s/sha256: .*/sha256: $checksum/" "${PACKAGE_NAME}-feedstock/recipe/meta.yaml"


if !(conda-verify ${PACKAGE_NAME}-feedstock/); then
    echo "------------------$PACKAGE_NAME:pre conda-verify fails-------------------------------------"
    exit 1
fi

if !(conda-build ${PACKAGE_NAME}-feedstock/); then
    echo "------------------$PACKAGE_NAME:conda-build fails-------------------------------------"
    exit 2
fi

# extracting path for generated binary tar.bz2

# Check if the tar.bz2 file exists in linux-ppc64le directory
linux_file="/root/miniconda/envs/$PACKAGE_NAME/conda-bld/linux-ppc64le/*.tar.bz2"
if ls $linux_file 1> /dev/null 2>&1; then
   binary_path=$(ls $linux_file)
   echo "Found $PACKAGE_NAME.tar.bz2 in linux-ppc64le directory."
else
   echo "$PACKAGE_NAME.tar.bz2 not found in linux-ppc64le directory. Searching in noarch directory..."
   # If not found in linux directory, search in noarch directory
   found_file=$(find "/root/miniconda/envs/$PACKAGE_NAME/conda-bld/noarch" -name "*.tar.bz2" -type f -print -quit)
   if [ -n "$found_file" ]; then
       binary_path="$found_file"
       echo "Found $PACKAGE_NAME.tar.bz2 in noarch directory."
   else
       echo "Error: $PACKAGE_NAME.tar.bz2 file not found in linux-ppc64le or noarch directory."
       exit 3
   fi
fi

# Print the binary_path variable
echo "binary file found: $binary_path"

#verifying tar.bz2 generated by conda-build
if !(conda-verify $binary_path); then
    echo "------------------$PACKAGE_NAME:post conda-verify fails-------------------------------------"
    exit 4
fi

#installing package from tar.bz2 file generated by conda-build
if !(conda install -y $PACKAGE_NAME -c file://${binary_path%/*}); then
    echo "------------------$PACKAGE_NAME:conda install fails-------------------------------------"
    exit 5
fi

#version extraction of installed package
if ! conda_output=$(conda list | grep $PACKAGE_NAME); then
    echo "------------------$PACKAGE_NAME:conda list fails-------------------------------------"
    exit 6
fi

# Comparing extracted version with PACKAGE_VERSION
if ! [[ "$(echo $conda_output | awk '{print $8}')" == "$PACKAGE_VERSION" ]]; then
   echo "------------------$PACKAGE_NAME: conda version comparison fails-------------------------------------"
   exit 7
else
   python_pkg_version=$(python3 -c "import $PACKAGE_NAME; print($PACKAGE_NAME.__version__)")
   if ! [[ "$python_pkg_version" == "$PACKAGE_VERSION" ]]; then
       echo "------------------$PACKAGE_NAME: version comparison fails-------------------------------------"
       exit 8
   else
       echo "--------------$PACKAGE_NAME Version: $python_pkg_version---------------"
       echo "--------------$PACKAGE_NAME: Build success and installation verified-------------------------"
       exit 0
   fi
fi
