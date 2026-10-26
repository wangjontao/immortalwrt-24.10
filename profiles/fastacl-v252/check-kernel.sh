#!/bin/sh
set -eu
# Run against the actual generated Linux .config after kernel preparation.
file=${1:?Usage: check-kernel.sh path/to/linux/.config}
for key in INET NETFILTER NF_CONNTRACK NF_TABLES NFT_CT NFT_NAT IP_ADVANCED_ROUTER IP_MULTIPLE_TABLES; do
  grep -Eq "^CONFIG_${key}=(y|m)$" "$file" || { echo "Kernel prerequisite absent: $key"; exit 1; }
done
for key in TUN NFT_TPROXY NETFILTER_XT_TARGET_TPROXY; do
  grep -Eq "^CONFIG_${key}=(y|m)$" "$file" || { echo "Kernel prerequisite absent: $key"; exit 1; }
done
echo 'sing-box TPROXY/TUN kernel prerequisites passed'
