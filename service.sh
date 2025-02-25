MODDIR="${0%/*}"

best_tcc() {
  for tcc in "${@}"; do
    sysctl 'net.ipv4.tcp_available_congestion_control' | grep -q "${tcc}" \
      && sysctl -qw "net.ipv4.tcp_congestion_control=${tcc}" && break
  done
}

best_dqd() {
  for dqd in "${@}"; do
    sysctl -qw "net.core.default_qdisc=${dqd}"
  done
}

# Zram
szblk='/sys/block/zram0'
if [[ -d "${szblk}" ]]; then
  swapoff /dev/zram0
  echo '1' > "${szblk}/reset"

  ## Best compression alg
  echo 'lz4' > "${szblk}/comp_algorithm"
  echo 'lzo-rle' > "${szblk}/comp_algorithm"
  echo 'zstd' > "${szblk}/comp_algorithm"  # Best

  ## Zram size
  sysmem="$(free -b | grep '^Mem:' | cut -d ' ' -f6)"
  halfmem="$((sysmem/2))"
  zramsize="$((sysmem + halfmem))"  # i.e. "*1.5"
  echo "${zramsize}" > "${szblk}/disksize"
  mkswap /dev/zram0
  swapon -d -p32767 /dev/zram0
fi

# i hope your device supports this
echo 'simple_ondemand' > /sys/kernel/gpu/gpu_governor

# blk tune
for sblk in /sys/block/*/queue; do
  echo 'noop' > "${sblk}/scheduler"
  echo 'none' > "${sblk}/scheduler"  # Best
  echo '512' > "${sblk}/read_ahead_kb"
  echo '128' > "${sblk}/nr_requests"
  echo '2' > "${sblk}/rq_affinity"
  echo '0' > "${sblk}/nomerges"
  echo '0' > "${sblk}/rotational"
done

# Clear cache
cmd package trim-caches 32G

# fstrim
mount -o "remount,noatime,lazytime,nodiscard,memory=normal,\
nobarrier,fsync_mode=nobarrier,atgc,flush_merge,checkpoint_merge\
active_logs=6,rw" /data

fstrim /data

# NTP
settings put global ntp_server 'pool.ntp.org'

# AOT compilation
cmd package compile -m speed -p PRIORITY_BACKGROUND -a --full &

# Wait for unblock
sleep 30
until [[ -d '/data/media/0/Android' ]]; do
  sleep 30
done

# start this if u need it)
stop logd

# Sleep mode
echo 'deep' > /sys/power/mem_sleep

# CPU
for cpf in /sys/devices/system/cpu/cpufreq/policy*; do
  echo 'schedutil' > "${cpf}/scaling_governor"
  echo '1000' > "${cpf}/schedutil/down_rate_limit_us"
  echo '1000' > "${cpf}/schedutil/up_rate_limit_us"
  echo '1' > "${cpf}/schedutil/pl"
done

# sysctl
sysctl -p "${MODDIR}/sysctl.conf"

best_tcc bbr cubic  # Right is the worst
best_dqd sfq fq_codel fq cake  # Right is the best  
