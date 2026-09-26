# Sourced by pixi on activation (see [activation] in pixi.toml).
#
# Prefers the system's libdrm over the environment's. SDL creates its GL
# context through the host's Mesa driver, which is built against the host's
# libdrm, but the environment's lib directory comes first on the search path,
# so Mesa gets conda-forge's copy instead. Once that copy is older than the
# one Mesa was built against, the driver fails to load on a missing symbol,
# and SDL reports it only as "Couldn't find matching GLX visual" or "Could
# not get EGL display". Preloading the system copies puts them first.
#
# A no-op where ldconfig knows no system libdrm (a container, say).
for _lib in libdrm.so.2 libdrm_amdgpu.so.1 libdrm_intel.so.1 \
    libdrm_nouveau.so.2 libdrm_radeon.so.1; do
    _path=$(/sbin/ldconfig -p 2>/dev/null \
        | awk -v lib="$_lib" '$1 == lib && /x86-64/ { print $NF; exit }')
    [ -n "$_path" ] && LD_PRELOAD="$_path${LD_PRELOAD:+ $LD_PRELOAD}"
done
unset _lib _path
[ -n "${LD_PRELOAD:-}" ] && export LD_PRELOAD
