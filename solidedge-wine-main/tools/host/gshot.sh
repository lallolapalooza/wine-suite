#!/bin/bash
# Capture the Windows guest screen to a png. usage: gshot.sh <out.png>
set -eu
out=${1:-/home/asdf/projects/solidedge-wine-main/state/vm/g.png}
ppm=${out%.png}.ppm
virsh screenshot win11 "$ppm" >/dev/null 2>&1
python3 -c "
from PIL import Image
im=Image.open('$ppm'); im.save('$out')
print('$out', im.size)
"
