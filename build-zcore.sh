#!/bin/sh

rm -rf output-zcore-*

packer build \
    --var-file="zcore-builder.json" \
    --var-file="zcore-13.7.json" \
    zcore.json

# Ensure the freshly created OVA is world-readable (644)
chmod 644 output-zcore-*/*.ova
